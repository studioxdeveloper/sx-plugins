# sx-plugins/scripts

Shared scripts fetched by CI workflows in the six STUDIO X plugin repos.

## validate-bilingual-triggers.py

Blocks PRs that add or modify a `SKILL.md` whose trigger list lacks a language required for its plugin.

### Plugin rules

| Plugin | Norwegian | English |
|---|---|---|
| `sx-core` | required | required |
| `sx-pm` | required | required |
| `sx-qa` | required | required |
| `pa-business` | optional | required |
| `sx-business` | required | optional |
| `sx-leadership` | required | optional |

### How it works

1. Lists added/modified `plugins/*/skills/*/SKILL.md` files in the PR via `git diff`.
2. Parses each file's frontmatter `description` (supports both single-line `"..."` and multi-line `>` forms).
3. Extracts trigger phrases from the `Trigger:` section.
4. Batches all triggers into one Claude Haiku 4.5 API call for language classification.
5. For each file: if any required language is missing, emits a `::error file=path::` annotation with 3–5 suggested phrases in the missing language.
6. Exits non-zero if any file failed.

### Why LLM classification (not regex)

Regex wordlists can't anticipate Norwegian compounds, declensions, and new words. Repeated audit attempts using regex produced many false positives. LLM judgment handles this reliably with negligible cost (~$0.01 per PR, well under $15/year across all six repos).

### Cost

Per typical PR (1–3 SKILL.md files changed): ~500–700 input tokens + ~200 output tokens via Haiku 4.5 — well under $0.01.

Cost cap: PRs with more than 100 trigger phrases skip the LLM check and emit a warning instead (this is a bulk maintenance PR, not a content change worth LLM-judging).

### Environment

Required env vars when run from a workflow:

- `ANTHROPIC_API_KEY` — org-level GitHub secret
- `GITHUB_REPOSITORY` — auto-set by GitHub Actions
- `BASE_REF` — set explicitly in the workflow (e.g. `${{ github.base_ref }}`)
- `IS_FORK_PR` — set in the workflow from `${{ github.event.pull_request.head.repo.fork }}`

### Exit codes

- `0` — all changed skills pass (or no skill changes / fork PR / cost cap)
- `1` — at least one skill failed
- `2` — configuration error (missing env var, missing dependency, etc.)

### Fork PRs

GitHub does not pass secrets to PRs from forks. The script detects fork PRs via `IS_FORK_PR` and emits a `::warning::` instead of running the check. A maintainer must re-run after bringing the PR into a branch on the main repo.

### Local testing

```bash
export ANTHROPIC_API_KEY="..."
export GITHUB_REPOSITORY="studioxdeveloper/sx-core"
export BASE_REF="main"

cd /path/to/sx-core
git fetch origin main
python3 /path/to/sx-plugins/scripts/validate-bilingual-triggers.py
```

### Workflow integration

Each plugin repo's `.github/workflows/validate-skills.yml` includes a step like:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0   # required for git diff against base ref

- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.11'

- name: Install anthropic SDK
  run: pip install anthropic

- name: Validate bilingual triggers
  env:
    ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
    BASE_REF: ${{ github.base_ref }}
    IS_FORK_PR: ${{ github.event.pull_request.head.repo.fork }}
  run: |
    curl -fsSL https://raw.githubusercontent.com/studioxdeveloper/sx-plugins/<PINNED_SHA>/scripts/validate-bilingual-triggers.py -o /tmp/v.py
    python3 /tmp/v.py
```

Pin `<PINNED_SHA>` to a specific commit, not `main`, for reproducibility.
