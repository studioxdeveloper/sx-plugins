# STUDIO X Plugins — Central Marketplace

> One marketplace, four plugins. Add this once in Claude Code or Claude Desktop, and you can install whichever plugins you need from a single place.

This repo is public, but most of the plugins it lists are private and require authorized GitHub access to the `studioxdeveloper` organization.

---

## ⚡ Recommended: One-shot installer

The fastest way to get everything set up — handles GitHub authentication, marketplace registration, plugin installation, and auto-updates:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/studioxdeveloper/sx-plugins/main/install.sh)
```

The script asks for your role (developer / PM / sales / partner) and installs the right plugins for you. Takes 2 minutes. Safe to run multiple times.

**No SSH setup required** — uses HTTPS via GitHub CLI authentication.

---

## What's here

This repo contains:
- `.claude-plugin/marketplace.json` — points to the four actual plugin repos
- `install.sh` — one-shot installer (recommended for new users)
- This README

The plugin code itself lives in separate private repos:

| Plugin | What it includes | Source repo |
|--------|------------------|-------------|
| **sx-core** | 105 technical skills + 41 agents + 4 hooks | studioxdeveloper/sx-core |
| **sx-business** | 32 Norwegian business skills (STUDIO X Norway only) | studioxdeveloper/sx-business |
| **pa-business** | 24 English business skills (Pettersson Apps only) | studioxdeveloper/pa-business |
| **sx-leadership** | 5 restricted pricing skills (leadership/sales only) | studioxdeveloper/sx-leadership |

---

## Manual installation (if the installer doesn't fit)

### Step 1: Add the marketplace ONCE

```bash
claude plugin marketplace add studioxdeveloper/sx-plugins
```

After this, all four plugins are visible in the Claude Code and Claude Desktop plugin menus.

### Step 2: Install what you need

In your terminal (Claude Code):
```bash
# All developers and PMs:
claude plugin install sx-core@studio-x-plugins

# STUDIO X Norway team:
claude plugin install sx-business@studio-x-plugins

# Pettersson Apps team:
claude plugin install pa-business@studio-x-plugins

# Leadership/sales only (requires specific GitHub access):
claude plugin install sx-leadership@studio-x-plugins
```

In Claude Desktop:
1. Open Customize → Plugins → Add marketplace
2. Paste `studioxdeveloper/sx-plugins`
3. Click Sync
4. Pick the plugins you want from the list and click Install

> **If you get a sync error in Claude Desktop**, your machine likely needs SSH keys set up for GitHub. The `install.sh` script avoids this entirely by using HTTPS authentication.

---

## Who installs what

| Role | sx-core | sx-business | pa-business | sx-leadership |
|------|:-------:|:-----------:|:-----------:|:-------------:|
| STUDIO X developer (Norway) | ✓ | ✓ | – | – |
| STUDIO X PM (Norway) | ✓ | ✓ | – | – |
| STUDIO X sales | ✓ | ✓ | – | ✓ |
| STUDIO X leadership (Rune) | ✓ | ✓ | – | ✓ |
| Pettersson Apps developer | ✓ | – | ✓ | – |
| Pettersson Apps PM | ✓ | – | ✓ | – |

**Access control**: GitHub permissions on each underlying source repo control who can actually install what. Pettersson Apps gets access to `sx-core` and `pa-business`, but not `sx-business` or `sx-leadership`. Listing plugins here does not grant access to the source code.

---

## Updates

Plugins installed from this marketplace are kept up to date with:

```bash
claude plugin update --all
```

Or automatically via the auto-update launchd agent (see `sx-core/skills/sx-auto-update` for setup).

---

## Why this exists

Before this central marketplace, users had to add four separate marketplaces:

```bash
claude plugin marketplace add studioxdeveloper/sx-core
claude plugin marketplace add studioxdeveloper/sx-business
claude plugin marketplace add studioxdeveloper/pa-business
claude plugin marketplace add studioxdeveloper/sx-leadership
```

Now it's one command, and all plugins are visible in a single picker UI. Less friction for new team members and partners.

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

The actual competitive advantage — the 105 skills, the kr-pricing tables, the canonical implementations — remains protected in the underlying private source repos. GitHub access controls who can clone and install each plugin.

---

*STUDIO X AS — Discovery layer is public. Plugin source code is private.*
