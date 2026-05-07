#!/usr/bin/env bash
# STUDIO X Plugin System — One-shot installer
# https://github.com/studioxdeveloper/sx-plugins
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/studioxdeveloper/sx-plugins/main/install.sh)
#
# This script:
#   1. Checks that gh CLI and claude CLI are installed (installs via Homebrew if missing)
#   2. Authenticates GitHub via web browser (no SSH setup needed)
#   3. Adds the studio-x-plugins marketplace
#   4. Asks for your role and installs the right plugins
#   5. Sets up automatic daily plugin updates via launchd
#
# Safe to run multiple times — skips steps that are already done.

set -e  # Exit on error

# ===== Sanity check: can we read interactive input? =====
# This script needs to ask the user questions. If stdin and /dev/tty
# are both unavailable, abort early with a clear message.
if [[ ! -e /dev/tty ]] && ! [ -t 0 ]; then
  echo "ERROR: This script needs an interactive terminal." >&2
  echo "       Run it with: bash <(curl -sSL https://raw.githubusercontent.com/studioxdeveloper/sx-plugins/main/install.sh)" >&2
  exit 1
fi

# Helper to read input — tries /dev/tty first, falls back to stdin
read_input() {
  local var_name="$1"
  if [[ -e /dev/tty ]]; then
    read -r "$var_name" < /dev/tty
  else
    read -r "$var_name"
  fi
}

# ===== Visual helpers =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

step() { echo -e "\n${BLUE}${BOLD}▶ $1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
ask()  { echo -en "  ${YELLOW}?${NC} $1"; }

# ===== Banner =====
cat <<'EOF'

  ███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗     ██╗  ██╗
  ██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗    ╚██╗██╔╝
  ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║     ╚███╔╝
  ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║     ██╔██╗
  ███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝    ██╔╝ ██╗
  ╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝     ╚═╝  ╚═╝

  Plugin System Installer
  https://github.com/studioxdeveloper/sx-plugins

EOF

# ===== Step 1: Check prerequisites =====
step "Step 1/5 — Checking prerequisites"

# Check macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
  warn "This installer is designed for macOS. Linux may work but is untested."
fi

# Check Homebrew
if ! command -v brew &>/dev/null; then
  err "Homebrew is required but not installed."
  echo "    Install from: https://brew.sh/"
  exit 1
fi
ok "Homebrew found"

# Check / install gh CLI
if ! command -v gh &>/dev/null; then
  warn "GitHub CLI (gh) not found — installing via Homebrew..."
  brew install gh
fi
ok "GitHub CLI found ($(gh --version | head -1))"

# Check claude CLI
if ! command -v claude &>/dev/null; then
  err "Claude Code CLI is not installed."
  echo "    Install Claude Code first: https://claude.com/code"
  exit 1
fi
ok "Claude Code CLI found"

# ===== Step 2: GitHub authentication =====
step "Step 2/5 — GitHub authentication"

if gh auth status &>/dev/null; then
  GITHUB_USER=$(gh api user --jq .login)
  ok "Already authenticated as: ${GITHUB_USER}"
else
  warn "Not authenticated to GitHub yet."
  echo "    Opening browser for one-time login..."
  echo "    (Press Enter when prompted, then complete login in browser)"
  echo ""
  gh auth login --web --hostname github.com --git-protocol https
  GITHUB_USER=$(gh api user --jq .login)
  ok "Authenticated as: ${GITHUB_USER}"
fi

# Configure git to use gh auth (no SSH needed)
gh auth setup-git
ok "Git configured to use gh auth (HTTPS, no SSH required)"

# Verify access to the studioxdeveloper organization
if gh api orgs/studioxdeveloper &>/dev/null; then
  ok "Access to studioxdeveloper organization confirmed"
else
  warn "You don't appear to have access to studioxdeveloper org"
  echo "    You may not be able to install all plugins."
  echo "    Contact rune@studiox.no to request access."
  echo ""
  ask "Continue anyway? [y/N] "
  read_input REPLY
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "    Aborted."
    exit 1
  fi
fi

# ===== Step 3: Add the marketplace =====
step "Step 3/5 — Adding STUDIO X marketplace"

if claude plugin marketplace list 2>/dev/null | grep -q "studio-x-plugins"; then
  ok "Marketplace already added — refreshing..."
  claude plugin marketplace update studioxdeveloper/sx-plugins 2>&1 | tail -1 || true
else
  echo "    Adding studioxdeveloper/sx-plugins..."
  claude plugin marketplace add studioxdeveloper/sx-plugins
fi

ok "Marketplace ready"

# ===== Step 4: Pick role and install plugins =====
step "Step 4/5 — Pick your role"

cat <<'EOF'

  Which role best describes you?

    1) STUDIO X Developer (Norway)        → sx-core + sx-business
    2) STUDIO X Project Manager (Norway)  → sx-core + sx-business
    3) STUDIO X Sales / Leadership        → sx-core + sx-business + sx-leadership
    4) Pettersson Apps Developer          → sx-core + pa-business
    5) Pettersson Apps Project Manager    → sx-core + pa-business
    6) Custom (pick plugins individually)
EOF

ask "Enter choice [1-6]: "
read_input ROLE

# Strip all whitespace and non-printable chars (handles terminal weirdness, paste artifacts)
ROLE="${ROLE//[[:space:]]/}"
ROLE="${ROLE//$'\r'/}"
ROLE="${ROLE//$'\n'/}"

PLUGINS_TO_INSTALL=()
if [[ "$ROLE" == "1" || "$ROLE" == "2" ]]; then
  PLUGINS_TO_INSTALL=("sx-core" "sx-business")
  ROLE_NAME="STUDIO X Norway"
elif [[ "$ROLE" == "3" ]]; then
  PLUGINS_TO_INSTALL=("sx-core" "sx-business" "sx-leadership")
  ROLE_NAME="STUDIO X Sales/Leadership"
elif [[ "$ROLE" == "4" || "$ROLE" == "5" ]]; then
  PLUGINS_TO_INSTALL=("sx-core" "pa-business")
  ROLE_NAME="Pettersson Apps"
elif [[ "$ROLE" == "6" ]]; then
  echo ""
  echo "    Available plugins:"
  echo "      • sx-core        — 105 technical skills (recommended for everyone)"
  echo "      • sx-business    — 32 Norwegian business skills"
  echo "      • pa-business    — 24 English business skills (Pettersson Apps)"
  echo "      • sx-leadership  — 5 restricted pricing skills (leadership/sales only)"
  echo ""
  for p in sx-core sx-business pa-business sx-leadership; do
    ask "Install ${p}? [y/N] "
    read_input REPLY
    REPLY="${REPLY//[[:space:]]/}"
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      PLUGINS_TO_INSTALL+=("$p")
    fi
  done
  ROLE_NAME="Custom"
else
  err "Invalid choice: '${ROLE}' (length: ${#ROLE})"
  echo "    Expected 1, 2, 3, 4, 5, or 6"
  echo "    Hex dump of input: $(printf '%s' "$ROLE" | xxd 2>/dev/null | head -1)"
  exit 1
fi

echo ""
ok "Role: ${ROLE_NAME}"
ok "Plugins to install: ${PLUGINS_TO_INSTALL[*]}"

step "Installing plugins"

for plugin in "${PLUGINS_TO_INSTALL[@]}"; do
  if claude plugin list 2>/dev/null | grep -q "${plugin}@"; then
    echo "    ${plugin} already installed — updating..."
    claude plugin update "${plugin}@studio-x-plugins" 2>&1 | tail -1 || \
    claude plugin update "${plugin}@${plugin}" 2>&1 | tail -1 || \
    warn "Could not update ${plugin} (may need manual intervention)"
    ok "${plugin} updated"
  else
    echo "    Installing ${plugin}..."
    if claude plugin install "${plugin}@studio-x-plugins" 2>&1 | tail -3; then
      ok "${plugin} installed"
    else
      err "Failed to install ${plugin}"
      echo "      You may not have access to this plugin's source repo."
      echo "      Contact rune@studiox.no if you should have access."
    fi
  fi
done

# ===== Step 5: Set up auto-update =====
step "Step 5/5 — Auto-update setup"

if [[ -f ~/Library/LaunchAgents/no.studiox.plugin-updater.plist ]]; then
  ok "Auto-update already configured"
else
  ask "Set up daily automatic plugin updates? [Y/n] "
  read_input REPLY
  if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
    # Run the auto-update installer from sx-core
    UPDATER_SCRIPT=$(find ~/.claude/plugins/cache/sx-core -name "install-updater.sh" 2>/dev/null | head -1)
    if [[ -n "$UPDATER_SCRIPT" && -x "$UPDATER_SCRIPT" ]]; then
      bash "$UPDATER_SCRIPT" || warn "Auto-update setup had issues — you can run it manually later"
      ok "Auto-update configured (runs daily at 09:00)"
    else
      warn "sx-auto-update installer not found in sx-core cache"
      echo "      You can set it up later by running:"
      echo "      bash ~/.claude/plugins/cache/sx-core/sx-core/*/skills/sx-auto-update/scripts/install-updater.sh"
    fi
  else
    echo "    Skipped. You can run auto-update setup later."
  fi
fi

# ===== Done =====
cat <<EOF


  ${GREEN}${BOLD}Installation complete!${NC}

  Next steps:
    1. Restart Claude Code (Cmd+Q and reopen) to load all skills
    2. Restart Claude Desktop too if you use it
    3. Try a prompt to verify — for example:
       "List all STUDIO X plugins available"

  Plugins installed: ${PLUGINS_TO_INSTALL[*]}
  Auto-update: $([[ -f ~/Library/LaunchAgents/no.studiox.plugin-updater.plist ]] && echo "enabled" || echo "not configured")

  Documentation:
    https://github.com/studioxdeveloper/sx-plugins

  Support:
    rune@studiox.no

EOF
