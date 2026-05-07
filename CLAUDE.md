# STUDIO X Plugin Marketplace

> **Dette repoet er IKKE en plugin.** Det er en marketplace-katalog som lister alle STUDIO X plugins.

**Status:** Aktiv — sentralisert plugin-discovery for hele organisasjonen.

---

## Repo-struktur

```
sx-plugins/
├── .claude-plugin/
│   └── marketplace.json    <- Listing av alle 4 plugins
├── CLAUDE.md
└── README.md
```

Det er bevisst MINIMAL — dette er ren konfigurasjon, ingen kode.

---

## Hvordan marketplace.json fungerer

Hver entry under `plugins` peker på en EKSTERN repo som inneholder den faktiske plugin-koden:

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

Dette lar oss ha:
- Én sentralisert oppdagelse-katalog (dette repoet)
- Distribuert kodebase (hvert plugin har eget repo, egen versjonering, egen branch protection)
- Granular GitHub-tilgangskontroll (sx-leadership-repo kan være låst til kun Rune+salg, mens sx-core er åpen for alle developers)

---

## Når oppdatere dette repoet

| Endring | Når |
|---------|-----|
| Nytt plugin i organisasjonen | Legg til i `plugins`-array |
| Plugin omdøpt eller flyttet | Oppdater `repo` eller `path` |
| Plugin avviklet | Fjern entry (eller marker som deprecated) |
| Beskrivelse av plugin endret | Oppdater `description` |

**Aldri push pluginens egne versjons-bumps hit.** Plugins versjoneres i sine egne repos.

---

## Distribusjon

| Plattform | Metode |
|-----------|--------|
| Claude Code | `claude plugin marketplace add studioxdeveloper/sx-plugins` |
| Claude Desktop | Customize → Plugins → Add marketplace → `studioxdeveloper/sx-plugins` |

---

*STUDIO X AS — Privat og konfidensielt*
