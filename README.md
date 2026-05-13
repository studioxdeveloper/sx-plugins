# STUDIO X Plugins — Central Marketplace

> One marketplace, six plugins. Add this once in Claude Code, and you can install whichever plugins you need from a single place.

This repo is public, but the plugins it lists are private and require authorized GitHub access to the `studioxdeveloper` organization.

---

## Two installation paths

### Path A — Claude Code (developers)

The fastest way to get everything set up — handles GitHub authentication, marketplace registration, plugin selection, and auto-updates:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/studioxdeveloper/sx-plugins/main/install.sh)
```

The script presents an interactive checkbox menu where you toggle which plugins to install (sx-core, sx-qa, and sx-pm pre-checked by default). Already-installed plugins are detected and pre-checked; unchecking them on a re-run uninstalls. Takes 2 minutes.

**No SSH setup required** — uses HTTPS via GitHub CLI authentication.

If GitHub's CDN is serving a stale cached copy, bypass it via the GitHub API:

```bash
rm -f /tmp/sx-install.sh && \
  gh api repos/studioxdeveloper/sx-plugins/contents/install.sh --jq .content | base64 -d > /tmp/sx-install.sh && \
  bash /tmp/sx-install.sh
```

### Path B — Claude Desktop / Cowork (non-developers)

Claude Desktop's "Add marketplace" UI cannot authenticate to private GitHub repos, so it cannot install plugins via marketplace URL. Instead, download the ZIP files from the GitHub Releases on each plugin repo and upload them via Claude Desktop UI.

**Where to download:**

| Plugin | Download |
|--------|----------|
| sx-core | **Claude Code only** — no Cowork zip (use sx-pm + sx-business instead) |
| sx-qa | [sx-qa/releases/latest](https://github.com/studioxdeveloper/sx-qa/releases/latest) |
| sx-pm | [sx-pm/releases/latest](https://github.com/studioxdeveloper/sx-pm/releases/latest) |
| sx-business | [sx-business/releases/latest](https://github.com/studioxdeveloper/sx-business/releases/latest) |
| pa-business | [pa-business/releases/latest](https://github.com/studioxdeveloper/pa-business/releases/latest) |
| sx-leadership | **NOT on GitHub Releases** — distributed manually by rune@studiox.no |

**Install steps:**

1. Download the zip(s) you need (you must have GitHub access to each plugin's source repo)
2. Open Claude Desktop → **Customize → Plugins → Personal → Local uploads**
3. Click the **+** icon → **Upload plugin**
4. Select the downloaded zip file
5. Restart Claude Desktop to activate skills

Repeat for each plugin you want to install.

> **For non-developers without GitHub access:** Contact rune@studiox.no to receive zip files directly via Slack, AirDrop, or 1Password.
>
> **For Cowork-only business users:** sx-core is Claude Code only and no longer publishes a Cowork zip. Install `sx-pm` (project management, bilingual) and `sx-business` (Norwegian sales templates) — that covers everything a PM, leader, or salesperson needs.

**Updates:** When a new version is released, download the new zip and upload it again. The newer version replaces the older one in Claude Desktop.

---

## What's here

This repo contains:
- `.claude-plugin/marketplace.json` — points to the five actual plugin repos
- `install.sh` — one-shot installer with interactive plugin picker
- This README

The plugin code itself lives in separate private repos:

| Plugin | What it includes | Source repo |
|--------|------------------|-------------|
| **sx-core** | 89 developer skills + 11 feature-templates + 40 agents + 3 hooks (Claude Code only) | studioxdeveloper/sx-core |
| **sx-qa** | 10 QA skills + 3 agents + 2 hooks + Maestro/Playwright MCP | studioxdeveloper/sx-qa |
| **sx-pm** | 16 bilingual (NO + EN) project management skills — kickoff, status, milestones, specs, estimation format | studioxdeveloper/sx-pm |
| **sx-business** | 19 Norwegian sales & delivery skills (STUDIO X Norway only) | studioxdeveloper/sx-business |
| **pa-business** | 24 English business skills (Pettersson Apps + STUDIO X) | studioxdeveloper/pa-business |
| **sx-leadership** | 5 restricted pricing skills (leadership/sales only) | studioxdeveloper/sx-leadership |

---

## Manual installation (if the installer doesn't fit)

### Step 1: Add the marketplace ONCE

```bash
claude plugin marketplace add studioxdeveloper/sx-plugins
```

After this, all six plugins are visible in the `claude plugin install` menu.

### Step 2: Install what you need

In your terminal (Claude Code):
```bash
# Everyone (recommended baseline):
claude plugin install sx-core@studio-x-plugins
claude plugin install sx-qa@studio-x-plugins
claude plugin install sx-pm@studio-x-plugins

# STUDIO X Norway team (sales / PM / delivery templates):
claude plugin install sx-business@studio-x-plugins

# Pettersson Apps team (developers + PMs):
claude plugin install pa-business@studio-x-plugins

# Leadership/sales only (requires specific GitHub access):
claude plugin install sx-leadership@studio-x-plugins
```

### About Claude Desktop

**You do NOT need to add the marketplace via Claude Desktop's UI.**

Claude Code and Claude Desktop share the same plugin directory (`~/.claude/plugins/`). When you install plugins via the terminal (using the installer script or `claude plugin install`), they automatically become available in Claude Desktop after you restart it.

> **Why "Add marketplace" in Desktop UI fails with sync error:** Claude Desktop's UI does not authenticate to GitHub, so it cannot validate the private source repos that this marketplace points to. The CLI works because `gh auth setup-git` configures git credentials. This is a limitation of Claude Desktop, not a configuration issue on your end.

**Just restart Claude Desktop after running the installer**, then go to Customize → Plugins to verify the plugins are listed. You don't need to interact with "Add marketplace" at all.

---

## Who installs what

| Role | sx-core | sx-qa | sx-pm | sx-business | pa-business | sx-leadership |
|------|:-------:|:-----:|:-----:|:-----------:|:-----------:|:-------------:|
| STUDIO X developer (Norway) | ✓ | ✓ | ✓ | ✓ | – | – |
| STUDIO X PM (Norway) | – | – | ✓ | ✓ | – | – |
| STUDIO X sales | – | – | ✓ | ✓ | – | ✓ |
| STUDIO X leadership (Rune) | ✓ | ✓ | ✓ | ✓ | – | ✓ |
| Pettersson Apps developer | ✓ | ✓ | ✓ | – | ✓ | – |
| Pettersson Apps PM | – | – | ✓ | – | ✓ | – |

**Access control**: GitHub permissions on each underlying source repo control who can actually install what. Pettersson Apps gets access to `sx-core`, `sx-qa`, `sx-pm`, and `pa-business`, but not `sx-business` or `sx-leadership`. Listing plugins here does not grant access to the source code.

---

## Updates

Plugins installed from this marketplace are kept up to date with:

```bash
claude plugin update --all
```

Or automatically via the auto-update launchd agent (see `sx-core/skills/sx-auto-update` for setup).

---

## Why this exists

Before this central marketplace, users had to add five separate marketplaces — one per plugin. Now it's one command, and all plugins are visible in a single picker UI. Less friction for new team members and partners.

---

## Maintenance (internal)

When a new plugin should be added to the listing:

1. Edit `.claude-plugin/marketplace.json`
2. Add a new entry to the `plugins` array
3. Commit and push to main
4. Users pick it up automatically the next time they run `claude plugin marketplace update`

---

## Why this repo is public while the plugin repos are private

This repo only contains pointers (plugin names + URLs). It contains no proprietary code, no pricing logic, no skill content. Making it public means:

- Claude Desktop's "Add marketplace" UI can fetch it without GitHub authentication
- New team members can run `claude plugin marketplace add ...` without first authenticating
- Onboarding is faster

The actual competitive advantage — the ~150 skills, the kr-pricing tables, the canonical implementations — remains protected in the underlying private source repos. GitHub access controls who can clone and install each plugin.

---

*STUDIO X AS — Discovery layer is public. Plugin source code is private.*
