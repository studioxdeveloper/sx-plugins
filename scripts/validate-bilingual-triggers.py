#!/usr/bin/env python3
"""
validate-bilingual-triggers.py — STUDIO X plugin CI gate.

Checks that any SKILL.md added or modified in this PR has trigger
phrases covering the required language(s) for its plugin.

Plugin rules
------------
- sx-core, sx-pm, sx-qa : BOTH Norwegian AND English required
- pa-business           : English required, Norwegian optional
- sx-business, sx-leadership : Norwegian only (English optional)

Environment variables
---------------------
- ANTHROPIC_API_KEY  : required (read by anthropic SDK)
- GITHUB_REPOSITORY  : "studioxdeveloper/sx-core" (set by GitHub Actions)
- BASE_REF           : base branch name, e.g. "main" (set in workflow)
- IS_FORK_PR         : "true" if PR is from a fork (set in workflow)

Exit codes
----------
- 0 : all good (or skipped — no skill changes / fork-PR warning / cost cap)
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

try:
    from anthropic import Anthropic
except ImportError:
    print(
        "::error::Missing 'anthropic' Python package. "
        "Add 'pip install anthropic' to the workflow before running this script."
    )
    sys.exit(2)


# ── Plugin rules ─────────────────────────────────────────────────────────────

PLUGIN_RULES = {
    "sx-core":       {"require_no": True,  "require_en": True},
    "sx-pm":         {"require_no": True,  "require_en": True},
    "sx-qa":         {"require_no": True,  "require_en": True},
    "pa-business":   {"require_no": False, "require_en": True},
    "sx-business":   {"require_no": True,  "require_en": False},
    "sx-leadership": {"require_no": True,  "require_en": False},
}

# Hard cap on trigger count per PR (cost protection)
MAX_TRIGGERS_PER_PR = 100

# Pinned model — classification is well within Haiku's capability
MODEL = "claude-haiku-4-5"


# ── Output helpers ───────────────────────────────────────────────────────────

def fail(msg: str, code: int = 2) -> "None":
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


def parse_frontmatter_description(path: Path) -> str:
    """Extract the `description` value from SKILL.md frontmatter.
    Handles both single-line quoted form and multi-line block form."""
    text = path.read_text(encoding="utf-8")
    fm_match = _FM_RE.match(text)
    if not fm_match:
        return ""
    fm = fm_match.group(1)

    # Try single-line "..." first
    sl = _DESC_SINGLE_RE.search(fm)
    if sl:
        return sl.group(2)

    # Try block form: description: >\n  line1\n  line2
    bl = _DESC_BLOCK_RE.search(fm)
    if bl:
        lines = [line.strip() for line in bl.group(1).splitlines() if line.strip()]
        return " ".join(lines)

    return ""


_TRIGGER_QUOTED_RE = re.compile(r"['\"]([^'\"]+)['\"]")


def extract_triggers(description: str) -> list[str]:
    """Extract trigger phrases from the description's `Trigger:` section."""
    idx = description.lower().find("trigger:")
    if idx < 0:
        return []
    trigger_text = description[idx + len("trigger:"):]
    raw = _TRIGGER_QUOTED_RE.findall(trigger_text)
    seen: set[str] = set()
    result: list[str] = []
    for phrase in raw:
        norm = phrase.strip()
        if norm and norm.lower() not in seen:
            seen.add(norm.lower())
            result.append(norm)
    return result


# ── Claude API ───────────────────────────────────────────────────────────────

CLASSIFY_PROMPT = """You are a Norwegian/English language classifier for STUDIO X plugin trigger phrases.

For each trigger phrase, classify the language as:
- "no" — clearly Norwegian (Norwegian word, æøå chars, Norwegian compound/declension, Norwegian-specific concept)
- "en" — clearly English (English word or phrase)
- "neutral" — language-agnostic: proper noun (e.g. "BankID", "Supabase"), acronym (e.g. "RLS"), code identifier (e.g. ".env", "convex env"), technical term that's the same in both languages

A file passes only if it has at least one trigger in each REQUIRED language for its plugin (see require_no / require_en flags per file). Neutral triggers don't count toward either language.

For any file MISSING a required language, suggest 3-5 specific trigger phrases in that language that fit the skill's actual purpose (use the description_excerpt to understand what the skill does).

Output a single JSON object only — no preamble, no commentary, no code fences.

Input:
{input_json}

Output schema:
{{
  "files": [
    {{
      "path": "string",
      "missing": ["no" or "en"],     // empty array if file passes
      "suggestions": {{               // present only if missing is non-empty
        "no": ["phrase 1", "phrase 2", ...],
        "en": ["phrase 1", "phrase 2", ...]
      }}
    }}
  ]
}}
"""


def _strip_code_fences(text: str) -> str:
    """Remove ```json ... ``` fences if the model wrapped its output."""
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*\n?", "", text)
        text = re.sub(r"\n?```\s*$", "", text)
    return text.strip()


def classify_with_claude(files_data: list[dict]) -> dict:
    """Send all files' triggers to Claude in one batched call."""
    client = Anthropic()  # reads ANTHROPIC_API_KEY from env
    response = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        messages=[{
            "role": "user",
            "content": CLASSIFY_PROMPT.format(
                input_json=json.dumps(files_data, ensure_ascii=False, indent=2)
            ),
        }],
    )
    raw = response.content[0].text
    cleaned = _strip_code_fences(raw)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as e:
        fail(
            f"Claude returned invalid JSON: {e}\n"
            f"--- raw response (first 2000 chars) ---\n{raw[:2000]}"
        )


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
            "PR is from a fork — secrets unavailable. Skipping bilingual trigger "
            "validation. A maintainer must re-run after bringing the PR into the main repo."
        )
        return 0

    if not os.environ.get("ANTHROPIC_API_KEY"):
        fail("ANTHROPIC_API_KEY is not set. Configure it as a GitHub org secret.")

    changed = list_changed_skill_files(base_ref)
    if not changed:
        info(f"[{plugin}] No SKILL.md changes in this PR. Skipping bilingual check.")
        return 0

    info(
        f"[{plugin}] Rule: require_no={rule['require_no']}, "
        f"require_en={rule['require_en']}"
    )
    info(f"[{plugin}] {len(changed)} SKILL.md file(s) to check:")

    files_data: list[dict] = []
    total_triggers = 0
    for path_str in changed:
        path = Path(path_str)
        if not path.exists():
            continue
        desc = parse_frontmatter_description(path)
        triggers = extract_triggers(desc)
        info(f"  - {path_str} ({len(triggers)} triggers)")
        files_data.append({
            "path": path_str,
            "description_excerpt": desc[:500],
            "triggers": triggers,
            "require_no": rule["require_no"],
            "require_en": rule["require_en"],
        })
        total_triggers += len(triggers)

    if total_triggers == 0:
        info(f"[{plugin}] No triggers extracted from changed files. Skipping.")
        return 0

    if total_triggers > MAX_TRIGGERS_PER_PR:
        warn(
            f"PR contains {total_triggers} trigger phrases (cap: {MAX_TRIGGERS_PER_PR}). "
            f"Skipping LLM check for cost protection — manual review recommended."
        )
        return 0

    info(f"[{plugin}] Classifying {total_triggers} trigger(s) via {MODEL}...")
    result = classify_with_claude(files_data)

    failures: list[tuple[str, list[str], dict]] = []
    for f in result.get("files", []):
        path = f.get("path", "?")
        missing = f.get("missing") or []
        suggestions = f.get("suggestions") or {}

        if missing:
            failures.append((path, missing, suggestions))
            for lang in missing:
                lang_full = "Norwegian" if lang == "no" else "English"
                suggested = suggestions.get(lang, [])
                msg = (
                    f"{path}: trigger list is missing {lang_full} coverage. "
                    f"Add at least one {lang_full} trigger to the description's "
                    f"Trigger: section."
                )
                if suggested:
                    quoted = ", ".join(f"'{s}'" for s in suggested[:5])
                    msg += f" Suggested: {quoted}"
                print(f"::error file={path}::{msg}")
        else:
            info(f"  ✓ {path} has all required languages")

    if failures:
        print()
        print(
            f"::error::Bilingual trigger validation failed for "
            f"{len(failures)} of {len(files_data)} changed file(s). See annotations above."
        )
        return 1

    info(f"\n[{plugin}] All {len(changed)} changed skill(s) pass bilingual trigger check.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
