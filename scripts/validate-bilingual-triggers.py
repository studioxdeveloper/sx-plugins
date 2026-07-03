#!/usr/bin/env python3
"""
validate-bilingual-triggers.py — STUDIO X plugin CI gate.

Checks that any SKILL.md added or modified in this PR has trigger
phrases covering the required language(s) for its plugin.

DESIGN: the pass/fail verdict is 100% DETERMINISTIC — charset (æøå) plus
curated word lists, no model call. The same commit always gets the same
verdict, and the gate works without any API key. Claude (temperature 0)
is used ONLY to generate suggested trigger phrases when a file fails;
suggestions never affect the exit code.

(The previous version let a default-temperature model decide pass/fail,
which made the gate non-deterministic: the same commit could flip between
green and red between reruns.)

Plugin rules
------------
- sx-core, sx-pm, sx-qa : BOTH Norwegian AND English required
- pa-business           : English required, Norwegian optional
- sx-business, sx-leadership : Norwegian only (English optional)

Environment variables
---------------------
- ANTHROPIC_API_KEY  : optional — enables suggestion generation on failure
- GITHUB_REPOSITORY  : "studioxdeveloper/sx-core" (set by GitHub Actions)
- BASE_REF           : base branch name, e.g. "main" (set in workflow)
- IS_FORK_PR         : "true" if PR is from a fork (set in workflow)

Exit codes
----------
- 0 : all good (or skipped — no skill changes / fork PR)
- 1 : at least one skill failed validation
- 2 : configuration error
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ── Plugin rules ─────────────────────────────────────────────────────────────

PLUGIN_RULES = {
    "sx-core":       {"require_no": True,  "require_en": True},
    "sx-pm":         {"require_no": True,  "require_en": True},
    "sx-qa":         {"require_no": True,  "require_en": True},
    "pa-business":   {"require_no": False, "require_en": True},
    "sx-business":   {"require_no": True,  "require_en": False},
    "sx-leadership": {"require_no": True,  "require_en": False},
}

# Suggestion generation only (never affects the verdict)
MODEL = "claude-haiku-4-5"
MAX_SUGGESTION_FILES = 20


# ── Deterministic language classification ───────────────────────────────────
#
# A trigger counts as Norwegian if it contains æ/ø/å or any word from
# NO_WORDS; as English if it contains any word from EN_WORDS. Everything
# else is neutral (proper nouns, acronyms, shared technical terms) and
# counts toward neither language. Words that exist in both languages or
# are language-agnostic in tech speech (app, design, test, status, sprint)
# are deliberately in NEITHER list.
#
# False negative (a genuinely Norwegian/English trigger classified
# neutral)? Add the missing word here in a normal PR — the gate stays
# deterministic forever after.

_NO_CHARS = re.compile(r"[æøåÆØÅ]")

NO_WORDS = {
    # verbs / imperatives
    "lag", "lage", "laget", "skriv", "skrive", "vis", "gi", "fiks", "fikse",
    "rett", "endre", "bytt", "oppdater", "korriger", "teste", "sjekk",
    "sjekke", "valider", "validere", "estimer", "estimere", "beregn",
    "beregne", "kalkuler", "kalkulere", "forbered", "forberede", "publiser",
    "publisere", "lansere", "forklar", "forklare", "vurder", "vurdere",
    "kvalifiser", "generer", "generere", "oversett", "planlegg",
    # nouns
    "tilbud", "tilbudet", "pris", "prisen", "prisliste", "regneark",
    "faktura", "brev", "rapport", "rapporten", "oversikt", "gjennomgang",
    "bruker", "brukere", "brukertesting", "akseptansetest", "sikkerhetsjekk",
    "kravspekk", "estimat", "estimatet", "timeestimat", "timer",
    "retningslinjer", "brukeropplevelse", "systemtest", "integrasjon",
    "integrasjoner", "kodebase", "kodebasen", "datamodell", "skjema",
    "tabeller", "relasjoner", "skjermbilde", "skjermbilder", "prosjekt",
    "prosjektet", "leveranse", "godkjenning", "innstillinger", "dokument",
    "dokumenter", "mal", "maler", "referat", "grovestimat", "vurdering",
    "henvendelse", "henvendelsen", "leaden", "budsjett", "kunde", "kunden",
    "appen", "arkitekturen", "utvikling", "vedlikehold", "nettapp",
    "nettside", "nettsiden", "progressiv",
    # function words / determiners common in Norwegian trigger phrases
    "hva", "hvordan", "hvilke", "hvilken", "denne", "dette", "disse",
    "mitt", "min", "mine", "nytt", "nye", "med", "uten", "til", "ikke",
    "norsk", "norske", "teknisk", "funksjonell", "delt",
}

EN_WORDS = {
    # verbs / imperatives
    "create", "make", "build", "write", "show", "generate", "update",
    "check", "validate", "estimate", "calculate", "prepare", "publish",
    "submit", "launch", "release", "explain", "assess", "qualify",
    "translate", "plan", "review",
    # nouns
    "pricing", "price", "cost", "breakdown", "phase", "feature", "features",
    "spreadsheet", "invoice", "letter", "report", "overview", "user",
    "experience", "guidelines", "navigation", "codebase", "architecture",
    "schema", "tables", "relations", "screen", "screens", "project",
    "delivery", "approval", "settings", "document", "documents", "template",
    "templates", "meeting", "proposal", "offer", "requirements", "budget",
    "customer", "client", "inquiry", "lead", "assessment", "estimation",
    "development", "maintenance",
    # function words common in English trigger phrases
    "what", "how", "which", "this", "these", "with", "without", "should",
    "the", "new", "technical", "functional", "shared", "english",
}

_WORD_RE = re.compile(r"[a-zA-ZæøåÆØÅ]+")


def classify_trigger(phrase: str) -> str:
    """Deterministically classify one trigger phrase: 'no' | 'en' | 'neutral'."""
    if _NO_CHARS.search(phrase):
        return "no"
    words = {w.lower() for w in _WORD_RE.findall(phrase)}
    if words & NO_WORDS:
        return "no"
    if words & EN_WORDS:
        return "en"
    return "neutral"


# ── Output helpers ───────────────────────────────────────────────────────────

def fail(msg: str, code: int = 2) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(code)


def warn(msg: str) -> None:
    print(f"::warning::{msg}")


def info(msg: str) -> None:
    print(msg)


# ── Git ──────────────────────────────────────────────────────────────────────

def run_git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        fail(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def list_changed_skill_files(base_ref: str) -> list[str]:
    """List added/modified SKILL.md files in this PR."""
    diff = run_git(
        "diff",
        "--name-only",
        "--diff-filter=AM",
        f"origin/{base_ref}...HEAD",
        "--",
        "plugins/*/skills/*/SKILL.md",
    )
    return [line for line in diff.splitlines() if line]


# ── Frontmatter parsing ──────────────────────────────────────────────────────

_FM_RE = re.compile(r"^---\n(.*?)\n---", re.DOTALL)
_DESC_SINGLE_RE = re.compile(
    r'^description:\s*(["\'])(.*?)\1\s*$', re.MULTILINE | re.DOTALL
)
_DESC_BLOCK_RE = re.compile(
    r'^description:\s*[>|][^\n]*\n((?:[ \t].*\n?)+)', re.MULTILINE
)
# Unquoted single-line scalar: description: Some text without quotes.
_DESC_PLAIN_RE = re.compile(r"^description:[ \t]*(?![\"'>|])(.+)$", re.MULTILINE)


def parse_frontmatter_description(path: Path) -> str:
    """Extract the `description` value from SKILL.md frontmatter.
    Handles both single-line quoted form and multi-line block form."""
    text = path.read_text(encoding="utf-8")
    fm_match = _FM_RE.match(text)
    if not fm_match:
        return ""
    fm = fm_match.group(1)

    sl = _DESC_SINGLE_RE.search(fm)
    if sl:
        return sl.group(2)

    bl = _DESC_BLOCK_RE.search(fm)
    if bl:
        lines = [line.strip() for line in bl.group(1).splitlines() if line.strip()]
        return " ".join(lines)

    pl = _DESC_PLAIN_RE.search(fm)
    if pl:
        return pl.group(1).strip()

    return ""


# Accepts the styles in use across the repos:
#   "Trigger: 'a', 'b'"         (sx-core/sx-pm quoted style)
#   "Trigger på: a, b"          (sx-business unquoted style)
#   "Norske triggere: 'a', 'b'" (appended NO sections)
_TRIGGER_SECTION_RE = re.compile(r"(?i)\btrigger[a-zæøå ]*:")
_TRIGGER_QUOTED_RE = re.compile(r"['\"]([^'\"]+)['\"]")


def extract_triggers(description: str) -> list[str]:
    """Extract trigger phrases from the first trigger-ish section onward.

    Quoted phrases win; if a trigger section exists but contains no quoted
    phrases, fall back to splitting the section text on commas (the
    unquoted 'Trigger på: a, b' style)."""
    m = _TRIGGER_SECTION_RE.search(description)
    if not m:
        return []
    trigger_text = description[m.end():]

    raw = _TRIGGER_QUOTED_RE.findall(trigger_text)
    if not raw:
        # Unquoted style: comma-separated words/phrases to end of description.
        raw = [p.strip(" .") for p in trigger_text.split(",")]
        raw = [p for p in raw if p and len(p) <= 60]

    seen: set[str] = set()
    result: list[str] = []
    for phrase in raw:
        norm = phrase.strip()
        if norm and norm.lower() not in seen:
            seen.add(norm.lower())
            result.append(norm)
    return result


# ── Suggestions (optional, never affects the verdict) ───────────────────────

SUGGEST_PROMPT = """For each file below, suggest 3-5 trigger phrases in the MISSING language(s) listed for it. The phrases must fit the skill's actual purpose (see description_excerpt) and be phrases a developer would naturally type.

Output a single JSON object only — no preamble, no code fences:
{{"files": [{{"path": "...", "suggestions": {{"no": [...], "en": [...]}}}}]}}

Input:
{input_json}
"""


def generate_suggestions(failed_files: list[dict]) -> dict[str, dict]:
    """Best-effort suggestion generation. Returns {path: {lang: [phrases]}}."""
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return {}
    if len(failed_files) > MAX_SUGGESTION_FILES:
        failed_files = failed_files[:MAX_SUGGESTION_FILES]
    try:
        from anthropic import Anthropic

        client = Anthropic()
        response = client.messages.create(
            model=MODEL,
            max_tokens=2048,
            temperature=0,
            messages=[{
                "role": "user",
                "content": SUGGEST_PROMPT.format(
                    input_json=json.dumps(failed_files, ensure_ascii=False)
                ),
            }],
        )
        raw = response.content[0].text.strip()
        raw = re.sub(r"^```(?:json)?\s*\n?", "", raw)
        raw = re.sub(r"\n?```\s*$", "", raw)
        data = json.loads(raw)
        return {
            f["path"]: f.get("suggestions", {})
            for f in data.get("files", [])
            if "path" in f
        }
    except Exception as e:  # suggestions are best-effort by design
        warn(f"Suggestion generation failed ({type(e).__name__}: {e}) — verdict unaffected.")
        return {}


# ── Main flow ────────────────────────────────────────────────────────────────

def main() -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    plugin = repo.split("/")[-1] if "/" in repo else repo
    base_ref = os.environ.get("BASE_REF", "main")
    is_fork = os.environ.get("IS_FORK_PR", "false").lower() == "true"

    if plugin not in PLUGIN_RULES:
        fail(
            f"Unknown plugin '{plugin}' (from GITHUB_REPOSITORY='{repo}'). "
            f"Add it to PLUGIN_RULES in validate-bilingual-triggers.py."
        )

    rule = PLUGIN_RULES[plugin]

    if is_fork:
        warn(
            "PR is from a fork — skipping bilingual trigger validation. "
            "A maintainer must re-run after bringing the PR into the main repo."
        )
        return 0

    changed = list_changed_skill_files(base_ref)
    if not changed:
        info(f"[{plugin}] No SKILL.md changes in this PR. Skipping bilingual check.")
        return 0

    info(
        f"[{plugin}] Rule: require_no={rule['require_no']}, "
        f"require_en={rule['require_en']} (deterministic verdict)"
    )

    failures: list[dict] = []
    for path_str in changed:
        path = Path(path_str)
        if not path.exists():
            continue
        desc = parse_frontmatter_description(path)
        triggers = extract_triggers(desc)

        langs = {classify_trigger(t) for t in triggers}
        missing: list[str] = []
        if rule["require_no"] and "no" not in langs:
            missing.append("no")
        if rule["require_en"] and "en" not in langs:
            missing.append("en")

        if not triggers:
            info(f"  ✗ {path_str}: no trigger section / no triggers found")
        elif missing:
            info(f"  ✗ {path_str}: {len(triggers)} triggers, langs={sorted(langs)}, missing={missing}")
        else:
            info(f"  ✓ {path_str}: {len(triggers)} triggers, langs={sorted(langs)}")

        if missing:
            failures.append({
                "path": path_str,
                "missing": missing,
                "description_excerpt": desc[:500],
                "triggers": triggers,
            })

    if not failures:
        info(f"\n[{plugin}] All {len(changed)} changed skill(s) pass bilingual trigger check.")
        return 0

    suggestions = generate_suggestions(failures)
    for f in failures:
        sugg = suggestions.get(f["path"], {})
        for lang in f["missing"]:
            lang_full = "Norwegian" if lang == "no" else "English"
            msg = (
                f"{f['path']}: trigger list is missing {lang_full} coverage "
                f"(deterministic check: charset + word lists). Add at least one "
                f"{lang_full} trigger to the description's Trigger: section."
            )
            phrases = sugg.get(lang, [])
            if phrases:
                msg += " Suggested: " + ", ".join(f"'{s}'" for s in phrases[:5])
            else:
                msg += (
                    " If an existing trigger IS in this language, add its main "
                    "word to the word list in validate-bilingual-triggers.py."
                )
            print(f"::error file={f['path']}::{msg}")

    print()
    print(
        f"::error::Bilingual trigger validation failed for "
        f"{len(failures)} of {len(changed)} changed file(s). See annotations above."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
