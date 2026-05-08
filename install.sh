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
# NOTE: this is overridden below if any plugin is already installed (we
# pre-check based on actual current state so the menu reflects reality).
declare -A PLUGIN_CHECKED=(
  ["sx-core"]=1
  ["sx-qa"]=1
  ["sx-business"]=0
  ["pa-business"]=0
)
# NOTE: sx-leadership is intentionally NOT listed here. It is distributed
# manually as a zip to leadership/sales only — never installable from this script.

# Detect what's currently installed and pre-check the menu accordingly.
# We also record the full plugin@marketplace id so we can update/uninstall
# the exact installed version, not assume @studio-x-plugins.
declare -A PLUGIN_INSTALLED_ID
INSTALLED_LIST=$(claude plugin list 2>/dev/null || true)
for p in "${PLUGIN_KEYS[@]}"; do
  existing_id=$(echo "$INSTALLED_LIST" | grep -oE "${p}@[a-zA-Z0-9_-]+" | head -1)
  if [[ -n "$existing_id" ]]; then
    PLUGIN_INSTALLED_ID[$p]="$existing_id"
    PLUGIN_CHECKED[$p]=1  # pre-check anything already installed
  fi
done

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

# Compute the diff between current state and chosen state:
#   - TO_INSTALL = checked AND not installed  → claude plugin install
#   - TO_UPDATE  = checked AND already installed → claude plugin update
#   - TO_REMOVE  = unchecked AND currently installed → claude plugin uninstall
TO_INSTALL=()
TO_UPDATE=()
TO_REMOVE=()
for p in "${PLUGIN_KEYS[@]}"; do
  is_installed=0
  [[ -n "${PLUGIN_INSTALLED_ID[$p]:-}" ]] && is_installed=1
  is_checked=0
  [[ "${PLUGIN_CHECKED[$p]}" == "1" ]] && is_checked=1

  if (( is_checked == 1 && is_installed == 0 )); then
    TO_INSTALL+=("$p")
  elif (( is_checked == 1 && is_installed == 1 )); then
    TO_UPDATE+=("$p")
  elif (( is_checked == 0 && is_installed == 1 )); then
    TO_REMOVE+=("$p")
  fi
done

# Show summary of planned actions
echo ""
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
  ok "Will install:   ${TO_INSTALL[*]}"
fi
if [[ ${#TO_UPDATE[@]} -gt 0 ]]; then
  ok "Will update:    ${TO_UPDATE[*]}"
fi
if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
  warn "Will uninstall: ${TO_REMOVE[*]}"
fi

if [[ ${#TO_INSTALL[@]} -eq 0 && ${#TO_UPDATE[@]} -eq 0 && ${#TO_REMOVE[@]} -eq 0 ]]; then
  ok "No changes — selection matches current state."
  echo ""
  echo "  Skipping to auto-update check..."
  SKIP_PLUGIN_OPS=1
fi

# Confirm before any uninstall (destructive)
if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
  echo ""
  ask "Confirm uninstall of: ${TO_REMOVE[*]} ? [y/N] "
  read_input REPLY
  REPLY="${REPLY//[[:space:]]/}"
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    warn "Skipping uninstall step — but proceeding with installs/updates."
    TO_REMOVE=()
  fi
fi

# ===== Pre-install access check =====
# Verify GitHub access to each new plugin to install BEFORE we attempt.
# (Updates of already-installed plugins are assumed to have access.)
if [[ -z "${SKIP_PLUGIN_OPS:-}" && ${#TO_INSTALL[@]} -gt 0 ]]; then
  step "Verifying GitHub access to new plugins"

  ACCESS_DENIED=()
  for plugin in "${TO_INSTALL[@]}"; do
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
    ask "Continue with the plugins you do have access to? [y/N] "
    read_input REPLY
    REPLY="${REPLY//[[:space:]]/}"
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
      echo "    Aborted. No changes made."
      exit 1
    fi
    FILTERED=()
    for p in "${TO_INSTALL[@]}"; do
      skip=0
      for d in "${ACCESS_DENIED[@]}"; do
        [[ "$p" == "$d" ]] && skip=1 && break
      done
      [[ "$skip" -eq 0 ]] && FILTERED+=("$p")
    done
    TO_INSTALL=("${FILTERED[@]}")
  fi
fi

# ===== Apply changes =====
if [[ -z "${SKIP_PLUGIN_OPS:-}" ]]; then
  step "Applying plugin changes"

  # Uninstall first (so a re-install in the same run works on fresh state)
  for plugin in "${TO_REMOVE[@]}"; do
    existing_id="${PLUGIN_INSTALLED_ID[$plugin]}"
    echo "    Uninstalling ${existing_id}..."
    if claude plugin uninstall "${existing_id}" 2>&1 | tail -1; then
      ok "${plugin} uninstalled"
    else
      err "Failed to uninstall ${plugin} (id: ${existing_id})"
    fi
  done

  # Update existing
  for plugin in "${TO_UPDATE[@]}"; do
    existing_id="${PLUGIN_INSTALLED_ID[$plugin]}"
    echo "    Updating ${existing_id}..."
    if claude plugin update "${existing_id}" 2>&1 | tail -1; then
      ok "${plugin} updated"
      if [[ "$existing_id" != "${plugin}@studio-x-plugins" ]]; then
        echo "      ℹ Tip: still on old marketplace (${existing_id}). To migrate:"
        echo "        claude plugin uninstall ${existing_id}"
        echo "        claude plugin install ${plugin}@studio-x-plugins"
      fi
    else
      err "Could not update ${plugin}"
    fi
  done

  # Install new
  for plugin in "${TO_INSTALL[@]}"; do
    echo "    Installing ${plugin}..."
    if claude plugin install "${plugin}@studio-x-plugins" 2>&1 | tail -3; then
      ok "${plugin} installed"
    else
      err "Failed to install ${plugin}"
    fi
  done
fi

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
# Build final state list from current claude plugin list (post-changes)
FINAL_LIST=$(claude plugin list 2>/dev/null | grep -oE "(sx-core|sx-qa|sx-business|pa-business|sx-leadership)@[a-zA-Z0-9_-]+" | sort -u | tr '\n' ' ')
[[ -z "$FINAL_LIST" ]] && FINAL_LIST="(none)"

cat <<EOF


  ${GREEN}${BOLD}Done!${NC}

  Next steps:
    1. Restart Claude Code (Cmd+Q and reopen) to load all skills
    2. Restart Claude Desktop too if you use it
    3. Try a prompt to verify — for example:
       "List all STUDIO X plugins available"

  Currently installed: ${FINAL_LIST}
  Auto-update: $([[ -f ~/Library/LaunchAgents/no.studiox.plugin-updater.plist ]] && echo "enabled" || echo "not configured")

  Documentation:
    https://github.com/studioxdeveloper/sx-plugins

  Support:
    rune@studiox.no

EOF
