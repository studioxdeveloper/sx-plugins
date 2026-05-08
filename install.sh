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
# ANSI-C quoting ($'...') so escape codes are interpreted at assignment time.
# This makes the variables work in cat <<EOF (heredoc) blocks too — not just
# in echo -e contexts.
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'  # No Color

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

# ===== Step 4: Pick plugins (toggle checkboxes) =====
step "Step 4/5 — Pick which plugins to install"

# Available plugins, in order shown to user.
# Each plugin has a label and an optional default state ("on" preselected).
PLUGIN_KEYS=("sx-core" "sx-qa" "sx-business" "pa-business")
declare -A PLUGIN_LABELS=(
  ["sx-core"]="105 technical skills (recommended for everyone)"
  ["sx-qa"]="10 QA skills + Maestro & Playwright MCP (companion to sx-core)"
  ["sx-business"]="32 Norwegian business skills"
  ["pa-business"]="24 English business skills (Pettersson Apps)"
)
# Default checked state — sx-core + sx-qa on by default, business plugins off.
declare -A PLUGIN_CHECKED=(
  ["sx-core"]=1
  ["sx-qa"]=1
  ["sx-business"]=0
  ["pa-business"]=0
)
# NOTE: sx-leadership is intentionally NOT listed here. It is distributed
# manually as a zip to leadership/sales only — never installable from this script.

N_PLUGINS=${#PLUGIN_KEYS[@]}
CURSOR=0

# Print quick guide once (above the menu — won't be redrawn)
echo ""
echo "    ${BOLD}Quick guide:${NC}"
echo "      STUDIO X Norway   → sx-core + sx-qa + sx-business"
echo "      Pettersson Apps   → sx-core + sx-qa + pa-business"
echo "      (sx-leadership is distributed manually — never via this script)"
echo ""
echo "    ${BOLD}↑↓${NC} move   ${BOLD}SPACE${NC} toggle   ${BOLD}1-${N_PLUGINS}${NC} jump-toggle   ${BOLD}ENTER${NC} confirm   ${BOLD}q${NC} quit"
echo ""

# Reserve N lines for the menu — redraw will overwrite these
for ((i=0; i<N_PLUGINS; i++)); do echo ""; done

# Hide cursor while in the menu (and restore on exit)
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null' EXIT

redraw_menu() {
  # Move cursor up to top of menu region
  tput cuu "$N_PLUGINS" 2>/dev/null
  local i=0
  for p in "${PLUGIN_KEYS[@]}"; do
    local mark="[ ]"
    [[ "${PLUGIN_CHECKED[$p]}" == "1" ]] && mark="${GREEN}[x]${NC}"
    local pointer="  "
    [[ "$i" -eq "$CURSOR" ]] && pointer="${BLUE}▶${NC} "
    tput el 2>/dev/null  # clear to end of line
    printf "      %b%d) %b  %-15s — %s\n" "$pointer" "$((i+1))" "$mark" "$p" "${PLUGIN_LABELS[$p]}"
    i=$((i+1))
  done
}

toggle_at() {
  local idx="$1"
  local key="${PLUGIN_KEYS[$idx]}"
  if [[ "${PLUGIN_CHECKED[$key]}" == "1" ]]; then
    PLUGIN_CHECKED[$key]=0
  else
    PLUGIN_CHECKED[$key]=1
  fi
}

# Pick input source — /dev/tty if available (works under bash <(curl…)),
# otherwise fall back to stdin.
TTY_IN=/dev/stdin
[[ -e /dev/tty ]] && TTY_IN=/dev/tty

redraw_menu

while true; do
  # Read a single byte (silent, no echo)
  IFS= read -rsn1 key < "$TTY_IN" || break

  case "$key" in
    $'\e')
      # Escape sequence — try to read the next two bytes (arrow keys)
      IFS= read -rsn2 -t 0.05 rest < "$TTY_IN" 2>/dev/null || rest=""
      case "$rest" in
        '[A')  # up
          (( CURSOR > 0 )) && CURSOR=$((CURSOR - 1))
          ;;
        '[B')  # down
          (( CURSOR < N_PLUGINS - 1 )) && CURSOR=$((CURSOR + 1))
          ;;
      esac
      ;;
    ' ')  # space toggles current
      toggle_at "$CURSOR"
      ;;
    '')  # Enter (empty read on newline)
      break
      ;;
    [1-9])
      n="$key"
      if (( n >= 1 && n <= N_PLUGINS )); then
        CURSOR=$((n - 1))
        toggle_at "$CURSOR"
      fi
      ;;
    q|Q)
      tput cnorm 2>/dev/null
      echo ""
      echo "    Aborted by user."
      exit 1
      ;;
    k|K)  # vim-style up
      (( CURSOR > 0 )) && CURSOR=$((CURSOR - 1))
      ;;
    j|J)  # vim-style down
      (( CURSOR < N_PLUGINS - 1 )) && CURSOR=$((CURSOR + 1))
      ;;
  esac
  redraw_menu
done

tput cnorm 2>/dev/null

# Build install list from checked items
PLUGINS_TO_INSTALL=()
for p in "${PLUGIN_KEYS[@]}"; do
  [[ "${PLUGIN_CHECKED[$p]}" == "1" ]] && PLUGINS_TO_INSTALL+=("$p")
done

if [[ ${#PLUGINS_TO_INSTALL[@]} -eq 0 ]]; then
  warn "No plugins selected — nothing to install. Exiting."
  exit 0
fi

echo ""
ok "Plugins to install: ${PLUGINS_TO_INSTALL[*]}"

# ===== Pre-install access check =====
# Verify GitHub access to each selected plugin's source repo BEFORE we attempt
# install. Saves the user from a confusing 403/404 mid-install.
step "Verifying GitHub access to selected plugins"

ACCESS_DENIED=()
for plugin in "${PLUGINS_TO_INSTALL[@]}"; do
  if gh api "repos/studioxdeveloper/${plugin}" &>/dev/null; then
    ok "${plugin} — access confirmed"
  else
    err "${plugin} — no access to studioxdeveloper/${plugin}"
    ACCESS_DENIED+=("$plugin")
  fi
done

if [[ ${#ACCESS_DENIED[@]} -gt 0 ]]; then
  echo ""
  warn "You don't have access to: ${ACCESS_DENIED[*]}"
  echo ""
  echo "    Possible reasons:"
  for p in "${ACCESS_DENIED[@]}"; do
    case "$p" in
      sx-business)
        echo "      • sx-business is for STUDIO X Norway only."
        echo "        If you're on the Pettersson Apps team, select ${BOLD}pa-business${NC} instead."
        ;;
      pa-business)
        echo "      • pa-business is for Pettersson Apps + STUDIO X."
        echo "        Contact rune@studiox.no to be added as collaborator."
        ;;
      *)
        echo "      • ${p}: contact rune@studiox.no for collaborator access,"
        echo "        or ask for the Cowork zip if you only use Claude Desktop."
        ;;
    esac
  done
  echo ""
  ask "Continue and install only the plugins you have access to? [y/N] "
  read_input REPLY
  REPLY="${REPLY//[[:space:]]/}"
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "    Aborted. No changes made."
    exit 1
  fi
  # Filter out denied plugins
  FILTERED=()
  for p in "${PLUGINS_TO_INSTALL[@]}"; do
    skip=0
    for d in "${ACCESS_DENIED[@]}"; do
      [[ "$p" == "$d" ]] && skip=1 && break
    done
    [[ "$skip" -eq 0 ]] && FILTERED+=("$p")
  done
  PLUGINS_TO_INSTALL=("${FILTERED[@]}")
  if [[ ${#PLUGINS_TO_INSTALL[@]} -eq 0 ]]; then
    err "Nothing left to install."
    exit 1
  fi
  ok "Continuing with: ${PLUGINS_TO_INSTALL[*]}"
fi

step "Installing plugins"

for plugin in "${PLUGINS_TO_INSTALL[@]}"; do
  # Find ANY existing installation of this plugin (regardless of marketplace).
  # The format is "<plugin>@<marketplace>" so we look for lines that start with
  # the plugin name followed by @.
  existing_id=$(claude plugin list 2>/dev/null | grep -oE "${plugin}@[a-zA-Z0-9_-]+" | head -1)

  if [[ -n "$existing_id" ]]; then
    echo "    ${plugin} already installed as ${existing_id} — updating..."
    if claude plugin update "${existing_id}" 2>&1 | tail -1; then
      ok "${plugin} updated (still on ${existing_id})"
      # If it's not from the new central marketplace, hint at migration
      if [[ "$existing_id" != "${plugin}@studio-x-plugins" ]]; then
        echo "      ℹ Tip: This plugin is from the old marketplace. To migrate to the central one:"
        echo "        claude plugin uninstall ${existing_id}"
        echo "        claude plugin install ${plugin}@studio-x-plugins"
      fi
    else
      err "Could not update ${plugin} (id: ${existing_id})"
      echo "      Try manually: claude plugin update ${existing_id}"
      echo "      Or reinstall:  claude plugin uninstall ${existing_id} && claude plugin install ${plugin}@studio-x-plugins"
    fi
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
