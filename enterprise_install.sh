#!/usr/bin/env bash
#
# Enterprise AI Dev Kit — Installer (macOS / Linux)
#
# Mirrors the structure of the official Databricks AI Dev Kit install.sh.
# Extends it with enterprise workspace selection, CA cert setup,
# compute configuration, and enterprise skills pulled from a private repo.
#
# Usage:
#   bash enterprise_install.sh                 # interactive
#   bash enterprise_install.sh --profile NAME  # skip profile prompt
#   bash enterprise_install.sh --force         # force reinstall
#   bash enterprise_install.sh --skills-only   # skip MCP server setup
#   bash enterprise_install.sh --global        # install globally (not per-project)
#
# Environment overrides (alternative to flags):
#   DEVKIT_PROFILE=NAME   bash enterprise_install.sh
#   DEVKIT_FORCE=true     bash enterprise_install.sh
#

set -e

# =============================================================================
# ── ENTERPRISE CONFIGURATION  (edit this section for your organisation) ──────
# =============================================================================

ENTERPRISE_NAME="McCain"
ENTERPRISE_DISPLAY="McCain"
ENTERPRISE_ORG="McCainFoods"    # GitHub org or user that owns the enterprise skills repo

# Enterprise skills source mode.
#   "git"   — clone/pull from a private remote repo (derived from ENTERPRISE_NAME + ENTERPRISE_ORG)
#   "local" — use a path on disk (set ENTERPRISE_SKILLS_PATH below; defaults to ./enterprise_skills/)
ENTERPRISE_SKILLS_MODE="git"

# Used when ENTERPRISE_SKILLS_MODE="git"
# Repo URL — defaults to <ENTERPRISE_ORG>/<ENTERPRISE_NAME>-skills if left as-is.
# Override with any SSH clone URL if your skills live in a different repo.
ENTERPRISE_SKILLS_REPO="git@github.com:${ENTERPRISE_ORG}/DAIA-data-architecture-skills.git"
# Subfolder inside the repo where skill directories live.
# Leave empty if skills are at the root of the repo.
# Example: "skills/enterprise"  or  "claude-skills"
ENTERPRISE_SKILLS_REPO_SUBPATH="mccain-data-architecture-skills"

# Used when ENTERPRISE_SKILLS_MODE="local"
# Leave empty to use the enterprise_skills/ folder inside this repo.
# Or set an absolute path to any directory that contains skill sub-folders.
ENTERPRISE_SKILLS_PATH=""

# GitHub Enterprise — set if your org uses GitHub Enterprise Server (not github.com).
# Example: "https://github.mccainfoods.com/api/v3"
# Leave empty to use public github.com.
GITHUB_API_URL=""

# Databricks workspace catalog — add or remove entries as domains change.
WORKSPACE_NAMES=(
    "Growth"
    "Supply Chain"
    "Finance"
    "Agriculture"
    "HR"
    "Procurement"
    "EDP"
    "Enter URL manually"
)
WORKSPACE_URLS=(
    "https://adb-982288893326755.15.azuredatabricks.net"
    "https://adb-1534255211069001.1.azuredatabricks.net"
    "https://adb-3107134495216511.11.azuredatabricks.net"
    "https://adb-54001242538101.1.azuredatabricks.net"
    "https://adb-2199059861738382.2.azuredatabricks.net"
    "https://adb-360325603937068.8.azuredatabricks.net"
    "https://adb-849096460664268.8.azuredatabricks.net"
    ""
)

# =============================================================================
# ── PATHS  (derived — do not edit) ───────────────────────────────────────────
# =============================================================================

# Script's own directory is always the repo root (cloned fork).
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

INSTALL_DIR="${AIDEVKIT_HOME:-$HOME/.ai-dev-kit}"
VENV_DIR="$INSTALL_DIR/.venv"
VENV_PYTHON="$VENV_DIR/bin/python"
MCP_ENTRY="$REPO_DIR/databricks-mcp-server/run_server.py"

ENTERPRISE_SKILLS_LOCAL="$REPO_DIR/enterprise_skills"
ENTERPRISE_SKILLS_REPO_DIR="$INSTALL_DIR/${ENTERPRISE_NAME}-skills-repo"
UPDATE_CHECK_CMD="bash $REPO_DIR/.claude-plugin/check_update.sh"
STATE_SUBDIR=".${ENTERPRISE_NAME}-adk"

# =============================================================================
# ── DEFAULTS  (overridable by flags / env vars) ───────────────────────────────
# =============================================================================

PROFILE="${DEVKIT_PROFILE:-DEFAULT}"
SCOPE="${DEVKIT_SCOPE:-project}"
FORCE="${DEVKIT_FORCE:-false}"
INSTALL_MCP=true
INSTALL_SKILLS=true
SKILLS_PROFILE=""
SILENT=false
PROFILE_PROVIDED=false

[ "$FORCE"  = "true" ] || [ "$FORCE"  = "1" ] && FORCE=true  || FORCE=false
[ "$SILENT" = "true" ] || [ "$SILENT" = "1" ] && SILENT=true || SILENT=false

PROJECT_DIR=""
WORKSPACE_URL=""

# =============================================================================
# ── PARSE FLAGS ───────────────────────────────────────────────────────────────
# =============================================================================

while [ $# -gt 0 ]; do
    case $1 in
        -p|--profile)      PROFILE="$2"; PROFILE_PROVIDED=true; shift 2 ;;
        -g|--global)       SCOPE="global"; shift ;;
        --skills-only)     INSTALL_MCP=false; shift ;;
        --mcp-only)        INSTALL_SKILLS=false; shift ;;
        --skills-profile)  SKILLS_PROFILE="$2"; shift 2 ;;
        --silent)          SILENT=true; shift ;;
        -f|--force)        FORCE=true; shift ;;
        -h|--help)
            echo ""
            echo "${ENTERPRISE_DISPLAY} Enterprise AI Dev Kit Installer"
            echo ""
            echo "Usage: bash enterprise_install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -p, --profile NAME     Databricks profile (default: DEFAULT)"
            echo "  -g, --global           Install globally (not per-project)"
            echo "  --skills-only          Skip MCP server setup"
            echo "  --mcp-only             Skip skills installation"
            echo "  --skills-profile LIST  Skill profiles: all,data-engineer,analyst,ai-ml-engineer,app-developer"
            echo "  --silent               No output except errors"
            echo "  -f, --force            Force reinstall"
            echo ""
            echo "Environment variables:"
            echo "  DEVKIT_PROFILE         Databricks config profile"
            echo "  DEVKIT_FORCE           Set to 'true' to force reinstall"
            echo "  AIDEVKIT_HOME          MCP install dir (default: ~/.ai-dev-kit)"
            echo ""
            exit 0 ;;
        *) echo "Unknown option: $1 (use -h for help)" >&2; exit 1 ;;
    esac
done

# =============================================================================
# ── OUTPUT HELPERS ────────────────────────────────────────────────────────────
# =============================================================================

# Colour codes — same as official ai-dev-kit install.sh
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1m'; D='\033[2m'; N='\033[0m'; CY='\033[0;36m'

msg()  { [ "$SILENT" = true ] || echo -e "  $*"; }
ok()   { [ "$SILENT" = true ] || echo -e "  ${G}✓${N} $*"; }
warn() { [ "$SILENT" = true ] || echo -e "  ${Y}!${N} $*"; }
die()  { echo -e "  ${R}✗${N} $*" >&2; exit 1; }
step() { [ "$SILENT" = true ] || echo -e "\n${CY}────────────────────────────────────────────────────────${N}\n  ${B}$*${N}\n${CY}────────────────────────────────────────────────────────${N}\n"; }

# =============================================================================
# ── INTERACTIVE HELPERS ───────────────────────────────────────────────────────
# =============================================================================

# Simple text prompt — reads from /dev/tty so it works with curl | bash
# Usage: result=$(prompt "Question" "default")
prompt() {
    local text="$1" default="$2" result=""
    if [ "$SILENT" = true ]; then echo "$default"; return; fi
    if [ -e /dev/tty ]; then
        printf "  %b [%s]: " "$text" "$default" > /dev/tty
        read -r result < /dev/tty
    elif [ -t 0 ]; then
        printf "  %b [%s]: " "$text" "$default"
        read -r result
    else
        echo "$default"; return
    fi
    [ -z "$result" ] && echo "$default" || echo "$result"
}

# ---------------------------------------------------------------------------
# radio_select — arrow-key single-choice selector, mirrors questionary.select
#
# Usage : radio_select "Title" "item1|value1|hint1" "item2|value2|hint2" ...
# Output: echoes the VALUE of the selected item to stdout
#
# Falls back to a numbered list when not running in a TTY.
# ---------------------------------------------------------------------------
radio_select() {
    local title="$1"; shift
    local -a labels=() values=() hints=()
    local count=0 cursor=0 selected=0

    for item in "$@"; do
        IFS='|' read -r label value hint <<< "$item"
        labels+=("$label"); values+=("$value"); hints+=("$hint")
        count=$((count + 1))
    done

    local total_rows=$((count + 2))   # items + blank + Confirm

    # ── Non-TTY fallback ────────────────────────────────────────────────────
    if ! [ -e /dev/tty ] || [ "$SILENT" = true ]; then
        printf "  %b%s%b\n" "$B" "$title" "$N" > /dev/tty 2>/dev/null || true
        local j=0
        for label in "${labels[@]}"; do
            printf "    %d) %s\n" $((j+1)) "$label"
            j=$((j+1))
        done
        printf "  Enter number [1]: "; local choice; read -r choice
        echo "${values[$(( ${choice:-1} - 1 ))]}"
        return
    fi

    # ── Draw function ────────────────────────────────────────────────────────
    _radio_draw() {
        printf "\033[%dA" "$total_rows" > /dev/tty
        local i=0
        for i in $(seq 0 $((count - 1))); do
            local arrow="    " dot="${D}○${N}" hint_style="$D"
            [ "$i" = "$cursor" ]   && arrow="  ${CY}❯${N} "
            [ "$i" = "$selected" ] && dot="${G}●${N}" && hint_style="$G"
            printf "\033[2K  %b%b%-22s %b%s%b\n" \
                "$arrow" "$dot " "${labels[$i]}" "$hint_style" "${hints[$i]}" "$N" > /dev/tty
        done
        printf "\033[2K\n" > /dev/tty
        if [ "$cursor" = "$count" ]; then
            printf "\033[2K  ${CY}❯${N} ${G}${B}[ Confirm ]${N}\n" > /dev/tty
        else
            printf "\033[2K    ${D}[ Confirm ]${N}\n" > /dev/tty
        fi
    }

    # Print title + hint, then reserve lines
    echo "" > /dev/tty
    printf "  %b%s%b\n" "$B" "$title" "$N" > /dev/tty
    printf "  %b↑/↓ navigate · Enter confirm%b\n\n" "$D" "$N" > /dev/tty
    for j in $(seq 0 $((total_rows - 1))); do printf "\n" > /dev/tty; done

    printf "\033[?25l" > /dev/tty   # hide cursor
    trap 'printf "\033[?25h" > /dev/tty 2>/dev/null' EXIT

    _radio_draw

    while true; do
        local key=""
        IFS= read -rsn1 key < /dev/tty 2>/dev/null

        if [ "$key" = $'\x1b' ]; then
            local s1="" s2=""
            IFS= read -rsn1 s1 < /dev/tty 2>/dev/null
            IFS= read -rsn1 s2 < /dev/tty 2>/dev/null
            if [ "$s1" = "[" ]; then
                case "$s2" in
                    A) [ "$cursor" -gt 0 ]    && cursor=$((cursor - 1)) ;;
                    B) [ "$cursor" -lt "$count" ] && cursor=$((cursor + 1)) ;;
                esac
            fi
        elif [ "$key" = "" ]; then
            # Enter — select current item (if on an item) and always confirm
            [ "$cursor" -lt "$count" ] && selected=$cursor
            _radio_draw; break
        elif [ "$key" = " " ]; then
            # Space — highlight without confirming
            [ "$cursor" -lt "$count" ] && selected=$cursor
        fi
        _radio_draw
    done

    printf "\033[?25h" > /dev/tty
    trap - EXIT
    echo "${values[$selected]}"
}

# =============================================================================
# ── BANNER ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
printf "${CY}╔════════════════════════════════════════════════════════╗${N}\n"
printf "${CY}║${N}   ${B}${ENTERPRISE_DISPLAY} — Enterprise AI Dev Kit Installer${N}${CY}         ║${N}\n"
printf "${CY}╚════════════════════════════════════════════════════════╝${N}\n"
echo ""

# =============================================================================
# ── STEP 1: PROJECT DIRECTORY ─────────────────────────────────────────────────
# =============================================================================

step "Step 1 of 9 — Project Directory"

if [ -n "${1:-}" ] && [ -d "$1" ]; then
    PROJECT_DIR="$(cd "$1" && pwd)"
    ok "Project dir: $PROJECT_DIR"
else
    PROJECT_DIR=$(prompt "Project directory" "$(pwd)")
    mkdir -p "$PROJECT_DIR"
    PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
    ok "Project dir: $PROJECT_DIR"
fi

# Compute scope-local state dir
STATE_DIR_PATH="$PROJECT_DIR/$STATE_SUBDIR"
[ "$SCOPE" = "global" ] && STATE_DIR_PATH="$INSTALL_DIR/$STATE_SUBDIR"

mkdir -p \
    "$PROJECT_DIR/.claude/skills" \
    "$STATE_DIR_PATH" \
    "$PROJECT_DIR/src/generated" \
    "$PROJECT_DIR/instruction-templates"

ok "Workspace directories created"

# =============================================================================
# ── STEP 2: PREREQUISITES ─────────────────────────────────────────────────────
# =============================================================================

step "Step 2 of 9 — Prerequisites"

# git
command -v git >/dev/null 2>&1 || die "git required.  Install: https://git-scm.com"
ok "git"

# npx (needed for Atlassian MCP and GitHub MCP)
if command -v npx >/dev/null 2>&1; then
    ok "npx ($(node --version 2>/dev/null || echo 'node version unknown'))"
else
    warn "npx not found — required for Atlassian MCP (Confluence + Jira) and GitHub MCP"
    msg "  Install Node.js: https://nodejs.org  or  brew install node"
fi

# SSH access to GitHub (needed only when pulling enterprise skills from a remote git repo)
if [ "$ENTERPRISE_SKILLS_MODE" = "git" ] && [ -n "$ENTERPRISE_SKILLS_REPO" ]; then
    ssh_out=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true)
    if echo "$ssh_out" | grep -q "Hi "; then
        ok "SSH access to github.com"
    else
        warn "SSH access to github.com not verified — private skills repo clone may fail"
        msg "  Configure SSH: ssh-keygen -t ed25519 && add public key to GitHub"
    fi
fi

# uv
if command -v uv >/dev/null 2>&1; then
    ok "$(uv --version)"
else
    warn "uv not found — installing…"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || die "uv install failed.  Run: curl -LsSf https://astral.sh/uv/install.sh | sh"
    ok "$(uv --version) (just installed)"
fi

# Databricks CLI
if command -v databricks >/dev/null 2>&1; then
    ok "Databricks CLI: $(databricks --version 2>&1 | head -1)"
else
    warn "Databricks CLI not found.  Install:"
    msg "  curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
    msg "  You can continue, but authentication will require the CLI later."
fi

# =============================================================================
# ── STEP 3: DATABRICKS WORKSPACE & PROFILE ────────────────────────────────────
# =============================================================================

step "Step 3 of 9 — Databricks Workspace & Profile"

# ── Workspace selection ───────────────────────────────────────────────────────
items=()
for i in "${!WORKSPACE_NAMES[@]}"; do
    url="${WORKSPACE_URLS[$i]:-}"
    hint="${url:-enter URL manually}"
    items+=("${WORKSPACE_NAMES[$i]}|${WORKSPACE_NAMES[$i]}|$hint")
done

WS_NAME=$(radio_select "Choose your Databricks domain / workspace:" "${items[@]}")

# Find matching URL
WORKSPACE_URL=""
for i in "${!WORKSPACE_NAMES[@]}"; do
    if [ "${WORKSPACE_NAMES[$i]}" = "$WS_NAME" ]; then
        WORKSPACE_URL="${WORKSPACE_URLS[$i]:-}"
        break
    fi
done

if [ -z "$WORKSPACE_URL" ]; then
    WORKSPACE_URL=$(prompt "Databricks workspace URL" "https://")
else
    ok "Workspace: $WS_NAME  →  $WORKSPACE_URL"
fi
WORKSPACE_URL="${WORKSPACE_URL%/}"

# ── Profile selection ─────────────────────────────────────────────────────────
if [ "$PROFILE_PROVIDED" = false ] && [ "$SILENT" = false ]; then
    DATABRICKS_CFG="$HOME/.databrickscfg"
    KNOWN_PROFILES=()

    if [ -f "$DATABRICKS_CFG" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^\[([a-zA-Z0-9_-]+)\]$ ]]; then
                KNOWN_PROFILES+=("${BASH_REMATCH[1]}")
            fi
        done < "$DATABRICKS_CFG"
    fi

    echo ""
    if [ "${#KNOWN_PROFILES[@]}" -gt 0 ]; then
        pitems=()
        for p in "${KNOWN_PROFILES[@]}"; do
            hint=""; [ "$p" = "DEFAULT" ] && hint="default"
            pitems+=("$p|$p|$hint")
        done
        pitems+=("Custom profile name...|__CUSTOM__|enter a name")

        PROFILE=$(radio_select "Choose Databricks profile:" "${pitems[@]}")

        if [ "$PROFILE" = "__CUSTOM__" ]; then
            PROFILE=$(prompt "Profile name" "DEFAULT")
        else
            ok "Profile: $PROFILE"
        fi
    else
        msg "No ~/.databrickscfg found — you can authenticate after install."
        PROFILE=$(prompt "Profile name" "DEFAULT")
    fi
fi

# ── OAuth login if not already authenticated ──────────────────────────────────
echo ""
if command -v databricks >/dev/null 2>&1; then
    AUTH_USER=$(databricks current-user me --profile "$PROFILE" --output json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('userName',''))" 2>/dev/null || true)

    if [ -n "$AUTH_USER" ]; then
        ok "Already authenticated as $AUTH_USER"
    else
        warn "Not authenticated — opening browser for OAuth login…"
        databricks auth login --host "$WORKSPACE_URL" --profile "$PROFILE"
    fi
fi

# =============================================================================
# ── STEP 4: AUTHENTICATION + CA CERTIFICATES ─────────────────────────────────
# =============================================================================

step "Step 4 of 9 — Authentication + CA Certificates"

if command -v databricks >/dev/null 2>&1; then
    AUTH_USER=$(databricks current-user me --profile "$PROFILE" --output json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('userName',''))" 2>/dev/null || true)
    if [ -n "$AUTH_USER" ]; then
        ok "Authenticated as $AUTH_USER"
    else
        warn "Auth could not be confirmed.  Re-authenticate later:"
        msg "  databricks auth login --host $WORKSPACE_URL --profile $PROFILE"
    fi
fi

# ── Corporate CA certificates ─────────────────────────────────────────────────
CA_BUNDLE="$HOME/.${ENTERPRISE_NAME}-adk/ca-bundle.pem"

if [ -n "${NODE_EXTRA_CA_CERTS:-}" ] && [ -f "$NODE_EXTRA_CA_CERTS" ]; then
    : # already configured — skip silently
else
    echo ""
    msg "Configuring corporate CA certificates…"
    mkdir -p "$(dirname "$CA_BUNDLE")"
    CERT_OK=false

    if [ "$(uname)" = "Darwin" ]; then
        # macOS — extract from system + root keychains
        security find-certificate -a -p \
            /Library/Keychains/System.keychain \
            /System/Library/Keychains/SystemRootCertificates.keychain \
            > "$CA_BUNDLE" 2>/dev/null && CERT_OK=true || true
    else
        # Linux — find the system bundle
        for bundle in /etc/ssl/certs/ca-certificates.crt \
                      /etc/pki/tls/certs/ca-bundle.crt \
                      /etc/ssl/ca-bundle.pem; do
            if [ -f "$bundle" ]; then cp "$bundle" "$CA_BUNDLE"; CERT_OK=true; break; fi
        done
    fi

    if [ "$CERT_OK" = true ]; then
        export NODE_EXTRA_CA_CERTS="$CA_BUNDLE"
        # Persist to shell profile
        SHELL_PROFILE=""
        case "${SHELL:-}" in
            */zsh)  SHELL_PROFILE="$HOME/.zshrc" ;;
            */bash) SHELL_PROFILE="$HOME/.bash_profile" ;;
        esac
        if [ -n "$SHELL_PROFILE" ] && ! grep -q "NODE_EXTRA_CA_CERTS" "$SHELL_PROFILE" 2>/dev/null; then
            { echo ""; echo "# Enterprise ADK — corporate CA for Claude Code";
              echo "export NODE_EXTRA_CA_CERTS=\"$CA_BUNDLE\""; } >> "$SHELL_PROFILE"
        fi
    else
        warn "Could not extract CA certs — set manually:"
        msg "  export NODE_EXTRA_CA_CERTS=/path/to/bundle.crt"
    fi
fi

# =============================================================================
# ── STEP 5: DATABRICKS MCP ───────────────────────────────────────────────────
# =============================================================================

step "Step 5 of 9 — Databricks MCP"

# ── MCP server venv ───────────────────────────────────────────────────────────
if [ "$INSTALL_MCP" = true ]; then
    msg "Setting up Databricks MCP server…"
    [ -d "$REPO_DIR/databricks-mcp-server" ] || die "databricks-mcp-server not found in $REPO_DIR"

    if "$VENV_PYTHON" -c "import databricks_mcp_server" 2>/dev/null; then
        [ "$FORCE" = true ] && msg "Force reinstall…" || { ok "MCP server already set up — skipping"; }
    fi

    if ! "$VENV_PYTHON" -c "import databricks_mcp_server" 2>/dev/null || [ "$FORCE" = true ]; then
        mkdir -p "$VENV_DIR"
        uv venv --python 3.11 --allow-existing "$VENV_DIR" -q 2>/dev/null || uv venv --allow-existing "$VENV_DIR" -q
        msg "Installing Python dependencies…"
        # --native-tls: use system certificate store (required behind corporate TLS-intercepting proxies)
        uv pip install --python "$VENV_PYTHON" --native-tls \
            -e "$REPO_DIR/databricks-tools-core" \
            -e "$REPO_DIR/databricks-mcp-server" --quiet
        "$VENV_PYTHON" -c "import databricks_mcp_server" 2>/dev/null || die "MCP server import failed after install."
        ok "MCP server ready  →  $VENV_DIR"
    fi
fi

# ── Write .mcp.json with Databricks entry ─────────────────────────────────────
MCP_CONFIG="$PROJECT_DIR/.mcp.json"
python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
existing.setdefault('mcpServers', {})['databricks'] = {
    'command': '$VENV_PYTHON',
    'args':    ['$MCP_ENTRY'],
    'defer_loading': True,
    'env': {'DATABRICKS_CONFIG_PROFILE': '$PROFILE'}
}
path.write_text(json.dumps(existing, indent=2) + '\n')
"
ok "Databricks MCP  →  $MCP_CONFIG"

# =============================================================================
# ── STEP 6: GITHUB MCP ───────────────────────────────────────────────────────
# =============================================================================

step "Step 6 of 9 — GitHub MCP"

# ── Add GitHub entry to .mcp.json ─────────────────────────────────────────────
python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
data = json.loads(path.read_text())
github_env = {'GITHUB_PERSONAL_ACCESS_TOKEN': ''}
if '$GITHUB_API_URL':
    github_env['GITHUB_API_URL'] = '$GITHUB_API_URL'
data['mcpServers']['github'] = {
    'command': 'npx',
    'args':    ['-y', '@modelcontextprotocol/server-github'],
    'env':     github_env
}
path.write_text(json.dumps(data, indent=2) + '\n')
"

# ── OAuth via gh CLI ──────────────────────────────────────────────────────────
msg "Authenticating GitHub MCP via OAuth…"
if command -v gh >/dev/null 2>&1; then
    GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)
    if [ -n "$GH_USER" ]; then
        ok "GitHub: already authenticated as $GH_USER"
    else
        msg "Opening browser for GitHub OAuth login…"
        gh auth login --web --git-protocol ssh
        GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)
    fi
    GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
    if [ -n "$GITHUB_TOKEN" ]; then
        python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
data = json.loads(path.read_text())
data['mcpServers']['github']['env']['GITHUB_PERSONAL_ACCESS_TOKEN'] = '$GITHUB_TOKEN'
path.write_text(json.dumps(data, indent=2) + '\n')
"
        ok "GitHub MCP authenticated as ${GH_USER:-unknown}"
    else
        warn "Could not retrieve GitHub token — edit GITHUB_PERSONAL_ACCESS_TOKEN in .mcp.json manually"
    fi
else
    warn "gh CLI not found — install it for OAuth: https://cli.github.com"
    warn "Or set GITHUB_PERSONAL_ACCESS_TOKEN manually in .mcp.json"
fi

# =============================================================================
# ── STEP 7: ATLASSIAN MCP ────────────────────────────────────────────────────
# =============================================================================

step "Step 7 of 9 — Atlassian MCP"

# ── Add Atlassian entry to .mcp.json ──────────────────────────────────────────
python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
data = json.loads(path.read_text())
data['mcpServers']['atlassian'] = {
    'command': 'npx',
    'args':    ['mcp-remote', 'https://mcp.atlassian.com/v1/mcp', '--transport', 'http-first']
}
path.write_text(json.dumps(data, indent=2) + '\n')
"
ok "Atlassian MCP entry added  →  $MCP_CONFIG"

# ── OAuth via mcp-remote (browser) ───────────────────────────────────────────
msg "Authenticating Atlassian MCP (Confluence + Jira) via OAuth…"
if command -v npx >/dev/null 2>&1; then
    do_atlassian=$(prompt "Authenticate with Atlassian now? (y/n)" "y")
    if [ "$do_atlassian" = "y" ] || [ "$do_atlassian" = "Y" ]; then
        msg "Starting OAuth flow — a browser window will open."
        msg "Sign in with your Atlassian account, then press Enter here to continue."
        echo ""
        npx mcp-remote https://mcp.atlassian.com/v1/mcp --transport http-first &
        ATLASSIAN_PID=$!
        sleep 4
        prompt "Press Enter after completing Atlassian authentication in the browser" ""
        kill "$ATLASSIAN_PID" 2>/dev/null || true
        ok "Atlassian MCP authenticated"
    else
        msg "Skipped — OAuth will prompt automatically on first MCP use."
        ok "Atlassian MCP configured"
    fi
else
    warn "npx not found — Atlassian MCP OAuth skipped. Install Node.js first."
fi

# =============================================================================
# ── STEP 8: SKILLS + SETTINGS ────────────────────────────────────────────────
# =============================================================================

step "Step 8 of 9 — Skills + Settings"

# ── Write .claude/settings.json ───────────────────────────────────────────────
SETTINGS_PATH="$PROJECT_DIR/.claude/settings.json"
python3 -c "
import json, pathlib
path = pathlib.Path('$SETTINGS_PATH')
path.parent.mkdir(parents=True, exist_ok=True)
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
hook_cmd = '$UPDATE_CHECK_CMD'
hooks = existing.setdefault('hooks', {})
session = hooks.setdefault('SessionStart', [])
# Only add if not already present
if not any('check_update.sh' in str(h) for g in session for h in g.get('hooks', [])):
    session.append({'hooks': [{'type': 'command', 'command': 'bash ' + hook_cmd, 'timeout': 5}]})
path.write_text(json.dumps(existing, indent=2) + '\n')
"
ok ".claude/settings.json  →  $SETTINGS_PATH"

# ── Install skills ─────────────────────────────────────────────────────────────
if [ "$INSTALL_SKILLS" = true ]; then
    echo ""
    msg "Installing skills…"
    SKILLS_DEST="$PROJECT_DIR/.claude/skills"
    mkdir -p "$SKILLS_DEST"

    # Databricks skills — from this repo
    DB_COUNT=0
    if [ -d "$REPO_DIR/databricks-skills" ]; then
        for skill_dir in "$REPO_DIR/databricks-skills"/*/; do
            name=$(basename "$skill_dir")
            [ "$name" = "TEMPLATE" ] && continue
            cp -r "$skill_dir" "$SKILLS_DEST/$name"
            DB_COUNT=$((DB_COUNT + 1))
        done
    fi
    ok "Databricks skills  ($DB_COUNT installed)"

    # Enterprise skills — git repo or local path, controlled by ENTERPRISE_SKILLS_MODE
    ENT_COUNT=0
    ENT_SOURCE=""

    if [ "$ENTERPRISE_SKILLS_MODE" = "git" ]; then
        # ── Git mode: clone / update the remote private repo ──────────────────
        if [ -z "$ENTERPRISE_SKILLS_REPO" ]; then
            warn "ENTERPRISE_SKILLS_MODE=git but ENTERPRISE_SKILLS_REPO is empty — skipping"
        elif [ -d "$ENTERPRISE_SKILLS_REPO_DIR/.git" ]; then
            current_remote=$(git -C "$ENTERPRISE_SKILLS_REPO_DIR" remote get-url origin 2>/dev/null || true)
            if [ "$current_remote" != "$ENTERPRISE_SKILLS_REPO" ]; then
                msg "Enterprise skills repo URL changed — re-cloning…"
                rm -rf "$ENTERPRISE_SKILLS_REPO_DIR"
                git clone -q --depth 1 "$ENTERPRISE_SKILLS_REPO" "$ENTERPRISE_SKILLS_REPO_DIR" 2>/dev/null \
                    && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                    || warn "Failed to re-clone enterprise skills repo"
            else
                git -C "$ENTERPRISE_SKILLS_REPO_DIR" fetch -q --depth 1 origin main 2>/dev/null
                git -C "$ENTERPRISE_SKILLS_REPO_DIR" reset --hard FETCH_HEAD 2>/dev/null \
                    && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                    || warn "Failed to update enterprise skills repo"
            fi
        else
            mkdir -p "$INSTALL_DIR"
            git clone -q --depth 1 "$ENTERPRISE_SKILLS_REPO" "$ENTERPRISE_SKILLS_REPO_DIR" 2>/dev/null \
                && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                || warn "Failed to clone enterprise skills repo ($ENTERPRISE_SKILLS_REPO)"
        fi
    else
        # ── Local mode: use explicit path or default to ./enterprise_skills/ ──
        local_path="${ENTERPRISE_SKILLS_PATH:-$ENTERPRISE_SKILLS_LOCAL}"
        if [ -d "$local_path" ]; then
            ENT_SOURCE="$local_path"
        else
            warn "Local enterprise skills path not found: $local_path"
        fi
    fi

    # Apply subfolder path if specified (git mode only)
    if [ -n "$ENT_SOURCE" ] && [ -n "$ENTERPRISE_SKILLS_REPO_SUBPATH" ]; then
        ENT_SOURCE="$ENT_SOURCE/$ENTERPRISE_SKILLS_REPO_SUBPATH"
        [ -d "$ENT_SOURCE" ] || { warn "Subfolder not found in repo: $ENTERPRISE_SKILLS_REPO_SUBPATH"; ENT_SOURCE=""; }
    fi

    if [ -n "$ENT_SOURCE" ] && [ -d "$ENT_SOURCE" ]; then
        for skill_dir in "$ENT_SOURCE"/*/; do
            name=$(basename "$skill_dir")
            [ "$name" = "TEMPLATE" ] && continue
            # Only copy directories that contain a SKILL.md
            [ -f "$skill_dir/SKILL.md" ] || continue
            cp -r "$skill_dir" "$SKILLS_DEST/$name"
            ENT_COUNT=$((ENT_COUNT + 1))
        done
        ok "Enterprise skills  ($ENT_COUNT installed)  ← $ENT_SOURCE"
    else
        warn "No enterprise skills source found — skipping"
    fi
fi

# =============================================================================
# ── STEP 9: WORKSPACE + VERSION LOCK ─────────────────────────────────────────
# =============================================================================

step "Step 9 of 9 — Workspace + Version Lock"

# ── .gitignore ────────────────────────────────────────────────────────────────
GITIGNORE="$PROJECT_DIR/.gitignore"
touch "$GITIGNORE"
for rule in "$STATE_SUBDIR/" ".claude/" ".mcp.json" "src/generated/" ".databricks/" ".env" "__pycache__/" "*.pyc"; do
    grep -qF "$rule" "$GITIGNORE" 2>/dev/null || echo "$rule" >> "$GITIGNORE"
done
ok ".gitignore updated"

# ── src/generated/README.md ───────────────────────────────────────────────────
GEN_README="$PROJECT_DIR/src/generated/README.md"
if [ ! -f "$GEN_README" ]; then
    cat > "$GEN_README" <<'EOF'
# Generated Code

This directory is managed by Claude Code.
All AI-generated code is placed here automatically.

> Do not manually edit files in this directory.
EOF
fi
ok "src/generated/README.md"

# ── instruction-templates/default.md ─────────────────────────────────────────
TMPL="$PROJECT_DIR/instruction-templates/default.md"
if [ ! -f "$TMPL" ]; then
    cat > "$TMPL" <<EOF
# Project Instructions

This project uses Databricks on the Lakehouse platform.
Enterprise: **${ENTERPRISE_DISPLAY}**
Workspace:  $WORKSPACE_URL

## Code Generation Rules
- ALL generated code MUST go into \`src/generated/\`
- Never write generated files outside \`src/generated/\`

## Active Skills
- **Databricks skills**: all skills from ai-dev-kit
- **enterprise-naming-convention**: naming standards for all assets
- **enterprise-dynamic-modeling**: config-driven transformation patterns
- **enterprise-data-governance**: PII tagging and data retention policies
- **enterprise-cost-optimization**: cluster policies and cost attribution

## Context
- Catalog: \`<set your catalog>\`
- Environment: \`dev | staging | prod\`
- Team: \`<set your team>\`
EOF
fi
ok "instruction-templates/default.md"

# ── metadata.json + version.lock ─────────────────────────────────────────────
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

python3 -c "
import json, pathlib

state = pathlib.Path('$STATE_DIR_PATH')
state.mkdir(parents=True, exist_ok=True)

meta = {
    'enterprise':    '$ENTERPRISE_NAME',
    'workspace_url': '$WORKSPACE_URL',
    'profile':       '$PROFILE',
    'project_root':  '$PROJECT_DIR',
    'created_at':    '$NOW',
}
meta_file = state / 'metadata.json'
if meta_file.exists():
    try:
        old = json.loads(meta_file.read_text())
        old.update({k: v for k, v in meta.items() if k != 'created_at'})
        meta = old
    except: pass
meta_file.write_text(json.dumps(meta, indent=2) + '\n')

lock = {
    'enterprise_adk':       'enterprise-install',
    'enterprise_skills':    'bundled',
    'databricks_workspace': '$WORKSPACE_URL',
    'installed_at':         '$NOW',
}
(state / 'version.lock').write_text(json.dumps(lock, indent=2) + '\n')
"

ok "$STATE_SUBDIR/metadata.json"
ok "$STATE_SUBDIR/version.lock"

# =============================================================================
# ── SUMMARY ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
printf "${G}╔════════════════════════════════════════════════════════╗${N}\n"
printf "${G}║   ✓  Workspace Ready                                   ║${N}\n"
printf "${G}╚════════════════════════════════════════════════════════╝${N}\n"
echo ""
printf "  ${B}%-20s${N} %s\n" "Project"           "$PROJECT_DIR"
printf "  ${B}%-20s${N} %s\n" "Enterprise"        "$ENTERPRISE_DISPLAY"
printf "  ${B}%-20s${N} %s\n" "Workspace"         "$WORKSPACE_URL"
printf "  ${B}%-20s${N} %s\n" "Profile"           "$PROFILE"
printf "  ${B}%-20s${N} %s\n" "Databricks skills" "${DB_COUNT:-0} installed"
printf "  ${B}%-20s${N} %s\n" "Enterprise skills" "${ENT_COUNT:-0} installed"
printf "  ${B}%-20s${N} %s\n" "MCP config"        "$MCP_CONFIG"
echo ""
echo "Next steps:"
printf "  1. Open your project in Claude Code:  ${CY}claude %s${N}\n" "$PROJECT_DIR"
echo "  2. MCP + skills are active — try: \"List my SQL warehouses\""
echo ""
