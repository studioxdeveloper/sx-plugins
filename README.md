# STUDIO X Plugins — Sentral Marketplace

> Én marketplace, fire plugins. Legg til denne ÉN gang i Claude Code eller Claude Desktop, og du kan installere det du trenger fra ett sted.

Privat repo — krever tilgang til `studioxdeveloper` GitHub-organisasjonen.

---

## Hva ligger her

Dette repoet inneholder kun en `.claude-plugin/marketplace.json` som peker på de fire faktiske plugin-repoene. Selve plugin-koden lever i sine egne repos:

| Plugin | Hva | Repo |
|--------|-----|------|
| **sx-core** | 105 tekniske skills + 41 agenter + 4 hooks | studioxdeveloper/sx-core |
| **sx-business** | 32 norske forretnings-skills (kun STUDIO X i Norge) | studioxdeveloper/sx-business |
| **pa-business** | 24 engelske forretnings-skills (kun Pettersson Apps) | studioxdeveloper/pa-business |
| **sx-leadership** | 5 begrensede prising-skills (kun ledelse/salg) | studioxdeveloper/sx-leadership |

---

## Installasjon

### Steg 1: Legg til marketplacen ÉN gang

```bash
claude plugin marketplace add studioxdeveloper/sx-plugins
```

Etter dette er alle fire plugins synlige i Claude Code og Claude Desktop sin plugin-meny.

### Steg 2: Installer det du trenger

I terminal (Claude Code):
```bash
# Alle utviklere og PMs:
claude plugin install sx-core@studio-x-plugins

# STUDIO X-team i Norge:
claude plugin install sx-business@studio-x-plugins

# Pettersson Apps:
claude plugin install pa-business@studio-x-plugins

# Kun ledelse/salg (krever spesifikk GitHub-tilgang):
claude plugin install sx-leadership@studio-x-plugins
```

I Claude Desktop:
1. Åpne Customize → Plugins → Add marketplace
2. Lim inn `studioxdeveloper/sx-plugins`
3. Klikk Sync
4. Velg pluginene du vil installere fra listen

---

## Hvem installerer hva

| Rolle | sx-core | sx-business | pa-business | sx-leadership |
|-------|:-------:|:-----------:|:-----------:|:-------------:|
| STUDIO X-utvikler (Norge) | ✓ | ✓ | – | – |
| STUDIO X PM (Norge) | ✓ | ✓ | – | – |
| STUDIO X salg | ✓ | ✓ | – | ✓ |
| STUDIO X ledelse (Rune) | ✓ | ✓ | – | ✓ |
| Pettersson Apps utvikler | ✓ | – | ✓ | – |
| Pettersson Apps PM | ✓ | – | ✓ | – |

**Tilgangskontroll**: GitHub-tilgang per repo styrer hvem som faktisk kan installere hva. Pettersson Apps får tilgang til sx-core og pa-business, men ikke sx-business eller sx-leadership.

---

## Oppdateringer

Pluginer hentet fra denne marketplacen oppdateres via:

```bash
claude plugin update --all
```

Eller automatisk via auto-update launchd-agenten (se sx-core/skills/sx-auto-update for oppsett).

---

## Hvordan dette skiller seg fra å installere fra hvert enkelt repo

Tidligere måtte brukeren legge til 4 separate marketplaces:

```bash
claude plugin marketplace add studioxdeveloper/sx-core
claude plugin marketplace add studioxdeveloper/sx-business
claude plugin marketplace add studioxdeveloper/pa-business
claude plugin marketplace add studioxdeveloper/sx-leadership
```

Nå er det én kommando, og pluginene er synlige i ett valg-grensesnitt.

---

## Vedlikehold (intern)

Når en ny plugin skal legges til i listen:

1. Rediger `.claude-plugin/marketplace.json`
2. Legg til ny entry i `plugins`-arrayet
3. Commit og push til main
4. Brukere får den automatisk neste gang de gjør `claude plugin marketplace update`

---

*STUDIO X AS — Privat og konfidensielt*
