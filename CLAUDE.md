# STUDIO X Plugin Marketplace

> **This repo is NOT a plugin.** It's a marketplace catalog that lists all STUDIO X plugins.

**Status:** Active — centralized plugin discovery for the entire organization.

---

## Repo structure

```
sx-plugins/
├── .claude-plugin/
│   └── marketplace.json    <- Listing of all 4 plugins
├── CLAUDE.md
└── README.md
```

Intentionally MINIMAL — this is pure configuration, no code.

---

## How marketplace.json works

Each entry under `plugins` points to an EXTERNAL repo that contains the actual plugin code:

```json
{
  "name": "sx-core",
  "source": {
    "source": "github",
    "repo": "studioxdeveloper/sx-core",
    "path": "plugins/sx-core"
  }
}
```

This pattern gives us:

- **Centralized discovery** — one catalog (this repo)
- **Distributed codebases** — each plugin has its own repo, version, and branch protection
- **Granular GitHub access control** — sx-leadership can be locked to Rune+sales, while sx-core is open to all developers

---

## Visibility

This repo is **public** so that Claude Desktop's "Add marketplace" UI can fetch it without GitHub authentication. The underlying plugin repos remain private, controlled by per-repo collaborator access.

This repo contains no proprietary code, only pointers — making it public has no security cost.

---

## When to update this repo

| Change | When |
|--------|------|
| New plugin in the organization | Add an entry to the `plugins` array |
| Plugin renamed or moved | Update `repo` or `path` |
| Plugin retired | Remove the entry (or mark as deprecated) |
| Plugin description changed | Update `description` |

**Never push the plugins' own version bumps here.** Plugins are versioned in their own source repos.

---

## Distribution

| Platform | Method |
|----------|--------|
| Claude Code (CLI) | `claude plugin marketplace add studioxdeveloper/sx-plugins` |
| Claude Desktop | Customize → Plugins → Add marketplace → `studioxdeveloper/sx-plugins` |

---

*STUDIO X AS — Discovery layer is public. Plugin source code is private.*
