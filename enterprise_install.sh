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

# Early sanity check — confirm this is the correct repo directory
if [ ! -d "$REPO_DIR/databricks-mcp-server" ] || [ ! -d "$REPO_DIR/databricks-tools-core" ]; then
    echo ""
    echo "  ✗ Could not locate the custom-ai-dev-kit repo at: $REPO_DIR" >&2
    echo "" >&2
    echo "  Do NOT copy this script — run it directly using its full path from any directory:" >&2
    echo "" >&2
    echo "    bash /path/to/custom-ai-dev-kit/enterprise_install.sh" >&2
    echo "" >&2
    echo "  You can run this from inside your project directory, e.g.:" >&2
    echo "    cd ~/my-project" >&2
    echo "    bash /path/to/custom-ai-dev-kit/enterprise_install.sh" >&2
    echo "" >&2
    exit 1
fi

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
SKILLS_ONLY=false
SKILLS_PROFILE=""
SILENT=false
PROFILE_PROVIDED=false

[ "$FORCE"  = "true" ] || [ "$FORCE"  = "1" ] && FORCE=true  || FORCE=false
[ "$SILENT" = "true" ] || [ "$SILENT" = "1" ] && SILENT=true || SILENT=false

PROJECT_DIR=""
WORKSPACE_URL=""
SKILLS_AUTH_MODE="ssh"   # overridden in Step 2 if SSH is not set up

# =============================================================================
# ── PARSE FLAGS ───────────────────────────────────────────────────────────────
# =============================================================================

while [ $# -gt 0 ]; do
    case $1 in
        -p|--profile)      PROFILE="$2"; PROFILE_PROVIDED=true; shift 2 ;;
        -g|--global)       SCOPE="global"; shift ;;
        --skills-only)     INSTALL_MCP=false; SKILLS_ONLY=true; shift ;;
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
            echo "  --skills-only          Fast path: only update skills (skip Steps 3-7, 9)"
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
warn "NOTE: Do NOT run the official Databricks install.sh alongside this script."
msg "  This enterprise installer fully replaces it. Running both will break the MCP config."
echo ""

# =============================================================================
# ── STEP 1: PROJECT DIRECTORY ─────────────────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = true ]; then
    # In skills-only mode just use the current directory — no prompt needed
    PROJECT_DIR="$(pwd)"
    ok "Project dir: $PROJECT_DIR"
else
    step "Step 1 of 9 — Project Directory"
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
    "$STATE_DIR_PATH"

if [ "$SKILLS_ONLY" = false ]; then
    mkdir -p \
        "$PROJECT_DIR/src/generated" \
        "$PROJECT_DIR/instruction-templates"
fi

ok "Workspace directories created"

# =============================================================================
# ── STEP 2: PREREQUISITES ─────────────────────────────────────────────────────
# =============================================================================

step "Step 2 of 9 — Prerequisites"

if [ "$SKILLS_ONLY" = false ]; then

# ── git ───────────────────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    ok "git $(git --version | awk '{print $3}')"
else
    # On macOS, invoking git may trigger Xcode CLI install prompt — try it
    if [ "$(uname)" = "Darwin" ]; then
        warn "git not found — attempting Xcode CLI install…"
        xcode-select --install 2>/dev/null || true
        sleep 5
    fi
    command -v git >/dev/null 2>&1 || die "git required. Install: https://git-scm.com"
    ok "git $(git --version | awk '{print $3}') (just installed)"
fi

# ── Node.js / npx (needed for GitHub MCP + Atlassian MCP) ────────────────────
if command -v npx >/dev/null 2>&1; then
    ok "Node.js $(node --version 2>/dev/null || echo '?') / npx"
else
    warn "Node.js not found — installing…"
    if command -v brew >/dev/null 2>&1; then
        brew install node --quiet \
            && ok "Node.js $(node --version 2>/dev/null) / npx (just installed)" \
            || warn "brew install node failed — install manually: https://nodejs.org"
    elif command -v apt-get >/dev/null 2>&1; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null \
            && sudo apt-get install -y nodejs 2>/dev/null \
            && ok "Node.js $(node --version 2>/dev/null) / npx (just installed)" \
            || warn "apt install node failed — install manually: https://nodejs.org"
    elif command -v yum >/dev/null 2>&1; then
        curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash - 2>/dev/null \
            && sudo yum install -y nodejs 2>/dev/null \
            && ok "Node.js $(node --version 2>/dev/null) / npx (just installed)" \
            || warn "yum install node failed — install manually: https://nodejs.org"
    else
        warn "No package manager found — install Node.js manually: https://nodejs.org"
    fi
fi

# ── uv (Python package manager for MCP server) ────────────────────────────────
if command -v uv >/dev/null 2>&1; then
    ok "$(uv --version)"
else
    warn "uv not found — installing…"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv >/dev/null 2>&1 || die "uv install failed. Run: curl -LsSf https://astral.sh/uv/install.sh | sh"
    ok "$(uv --version) (just installed)"
fi

# ── Databricks CLI ────────────────────────────────────────────────────────────
if command -v databricks >/dev/null 2>&1; then
    ok "Databricks CLI: $(databricks --version 2>&1 | head -1)"
else
    warn "Databricks CLI not found — installing…"
    if command -v brew >/dev/null 2>&1; then
        brew tap databricks/tap 2>/dev/null || true
        brew install databricks --quiet \
            && ok "Databricks CLI: $(databricks --version 2>&1 | head -1) (just installed)" \
            || { warn "brew install failed — trying curl installer…"
                 curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
                 command -v databricks >/dev/null 2>&1 \
                     && ok "Databricks CLI installed" \
                     || warn "Databricks CLI install failed — install manually and re-run"; }
    else
        curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
        command -v databricks >/dev/null 2>&1 \
            && ok "Databricks CLI installed" \
            || warn "Databricks CLI install failed — install manually and re-run"
    fi
fi

fi  # end SKILLS_ONLY skip

# ── gh CLI (needed for GitHub MCP OAuth + SSH key setup) ──────────────────────
if command -v gh >/dev/null 2>&1; then
    ok "gh CLI: $(gh --version 2>&1 | head -1)"
else
    warn "gh CLI not found — installing…"
    if command -v brew >/dev/null 2>&1; then
        brew install gh --quiet \
            && ok "gh CLI: $(gh --version 2>&1 | head -1) (just installed)" \
            || warn "brew install gh failed — install manually: https://cli.github.com"
    elif command -v apt-get >/dev/null 2>&1; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
            | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
            && sudo apt-get update -qq && sudo apt-get install -y gh 2>/dev/null \
            && ok "gh CLI: $(gh --version 2>&1 | head -1) (just installed)" \
            || warn "apt install gh failed — install manually: https://cli.github.com"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y 'dnf-command(config-manager)' 2>/dev/null || true
        sudo yum config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null \
            && sudo yum install -y gh 2>/dev/null \
            && ok "gh CLI: $(gh --version 2>&1 | head -1) (just installed)" \
            || warn "yum install gh failed — install manually: https://cli.github.com"
    else
        warn "No package manager found — install gh manually: https://cli.github.com"
    fi
fi

# ── SSH access to GitHub (needed for private enterprise skills repo) ──────────
if [ "$ENTERPRISE_SKILLS_MODE" = "git" ] && [ -n "$ENTERPRISE_SKILLS_REPO" ]; then
    # Derive HTTPS URL from SSH URL for fallback
    HTTPS_SKILLS_REPO=$(echo "$ENTERPRISE_SKILLS_REPO" | sed 's|git@github.com:|https://github.com/|')

    _ssh_check() { ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true; }

    # ── Dedicated McCain SSH key setup ────────────────────────────────────────
    # Uses ~/.ssh/id_ed25519_mccain — created once, reused across all projects.
    # Updates ~/.ssh/config so SSH always picks this key for github.com.
    _setup_mccain_ssh_key() {
        local mccain_key="$HOME/.ssh/id_ed25519_mccain"
        mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

        # Step 1: Generate key only if it does not already exist
        if [ ! -f "$mccain_key" ]; then
            msg "Generating dedicated McCain SSH key..."
            local git_email
            git_email=$(gh api user --jq '.email' 2>/dev/null || echo "")
            ssh-keygen -t ed25519 -C "${git_email:-mccain-adk}" -f "$mccain_key" -N "" < /dev/tty
            ok "McCain SSH key generated: $mccain_key"
        else
            ok "Existing McCain SSH key found — reusing"
        fi

        # Step 2: Register on GitHub only if not already there
        local local_fp
        local_fp=$(ssh-keygen -lf "${mccain_key}.pub" 2>/dev/null | awk '{print $2}') || true
        if [ -n "$local_fp" ] && gh ssh-key list 2>/dev/null | grep -q "$local_fp"; then
            ok "McCain SSH key already registered on GitHub"
        else
            local host_label="Enterprise ADK - $(hostname)"
            msg "Registering McCain SSH key on GitHub..."
            local add_err
            if add_err=$(gh ssh-key add "${mccain_key}.pub" --title "$host_label" 2>&1); then
                ok "McCain SSH key registered on GitHub ($host_label)"
            else
                warn "Could not register key: $add_err"
            fi
        fi

        # Step 3: Update ~/.ssh/config to always use this key for github.com
        local ssh_config="$HOME/.ssh/config"
        touch "$ssh_config" && chmod 600 "$ssh_config"
        python3 -c "
import re, pathlib
cfg = pathlib.Path('$ssh_config')
content = cfg.read_text() if cfg.exists() else ''
block = '\nHost github.com\n  IdentityFile $mccain_key\n  IdentitiesOnly yes\n'
new_content = re.sub(r'\nHost github\.com\n(?:[ \t]+[^\n]*\n)*', block, content)
if new_content == content:
    new_content = content.rstrip('\n') + block
cfg.write_text(new_content)
" 2>/dev/null || {
            grep -q "Host github.com" "$ssh_config" 2>/dev/null \
                || printf '\nHost github.com\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$mccain_key" >> "$ssh_config"
        }
        ok "~/.ssh/config updated to use McCain key"

        # Step 4: Load key into ssh-agent for this session
        eval "$(ssh-agent -s)" 2>/dev/null || true
        ssh-add "$mccain_key" 2>/dev/null || true
    }

    # ── Check current SSH session ─────────────────────────────────────────────
    ssh_out=$(_ssh_check)
    if echo "$ssh_out" | grep -q "Hi "; then
        gh_user=$(echo "$ssh_out" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
        ok "SSH access to github.com  (authenticated as: ${gh_user:-unknown})"
        SKILLS_AUTH_MODE="ssh"

        # Confirm this is the correct McCain corporate account
        if [ "$SILENT" = false ]; then
            confirm=$(prompt "Is '${gh_user:-unknown}' your McCain corporate GitHub account? (y/n)" "y")
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                msg "Re-authenticating — please sign in with your McCain account in the browser..."
                gh auth login --web --git-protocol https --scopes admin:public_key < /dev/tty || true
                gh auth setup-git 2>/dev/null || true

                # Set up dedicated McCain SSH key for the newly authenticated account
                _setup_mccain_ssh_key

                # Re-test SSH with the new McCain key
                msg "Re-testing SSH access..."
                ssh_out=$(_ssh_check)
                if echo "$ssh_out" | grep -q "Hi "; then
                    gh_user=$(echo "$ssh_out" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
                    ok "Re-authenticated as: ${gh_user:-unknown}"
                    SKILLS_AUTH_MODE="ssh"
                else
                    warn "SSH not confirmed after re-auth — will use HTTPS with gh credentials"
                    SKILLS_AUTH_MODE="https"
                fi
            fi
        fi

    else
        warn "SSH access to github.com not verified"
        echo ""
        do_setup=$(prompt "Authenticate with GitHub to set up SSH keys automatically? (y/n)" "y")
        if [ "$do_setup" = "y" ] || [ "$do_setup" = "Y" ]; then
            msg "Opening browser for GitHub authentication..."
            gh auth login --web --git-protocol https --scopes admin:public_key < /dev/tty || true
            gh auth setup-git 2>/dev/null || true

            # Set up dedicated McCain SSH key
            _setup_mccain_ssh_key

            # Re-test SSH
            msg "Re-testing SSH access..."
            ssh_out=$(_ssh_check)
            if echo "$ssh_out" | grep -q "Hi "; then
                gh_user=$(echo "$ssh_out" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
                ok "SSH access to github.com verified  (authenticated as: ${gh_user:-unknown})"
                SKILLS_AUTH_MODE="ssh"
            else
                warn "SSH not verified yet — will use HTTPS with gh credentials"
                SKILLS_AUTH_MODE="https"
            fi
        else
            msg "Skipped — enterprise skills will not be installed"
            msg "Re-run with:  bash $0 --skills-only  after setting up GitHub authentication"
            SKILLS_AUTH_MODE="skip"
        fi
    fi

    # ── Proactive repo access check ───────────────────────────────────────────
    if [ "$SKILLS_AUTH_MODE" != "skip" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        SKILLS_REPO_PATH=$(echo "$ENTERPRISE_SKILLS_REPO" | sed 's|git@github\.com:||;s|\.git$||')
        msg "Checking access to enterprise skills repo..."
        if gh api "repos/$SKILLS_REPO_PATH" >/dev/null 2>&1; then
            ok "Enterprise skills repo accessible"
        else
            warn "Account '${gh_user:-unknown}' does not have access to: $ENTERPRISE_SKILLS_REPO"
            msg "  Contact your administrator to get access, then re-run:"
            msg "    bash $0 --skills-only"
            msg "  Continuing with MCP and other setup..."
            SKILLS_AUTH_MODE="skip"
        fi
    fi
fi

# =============================================================================
# ── STEP 3: DATABRICKS WORKSPACE & PROFILE ────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = false ]; then

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
    # already configured — ensure npm also has it
    command -v npm >/dev/null 2>&1 && npm config set cafile "$NODE_EXTRA_CA_CERTS" 2>/dev/null || true
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
        # Configure npm to use the same CA bundle (fixes npx/mcp-remote SSL errors)
        command -v npm >/dev/null 2>&1 && npm config set cafile "$CA_BUNDLE" 2>/dev/null || true
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

fi  # end SKILLS_ONLY skip (Steps 3 + 4)

# =============================================================================
# ── STEP 5: DATABRICKS MCP ───────────────────────────────────────────────────
# =============================================================================

step "Step 5 of 9 — Databricks MCP"

# ── MCP server venv ───────────────────────────────────────────────────────────
if [ "$INSTALL_MCP" = true ]; then
    msg "Setting up Databricks MCP server…"
    [ -d "$REPO_DIR/databricks-mcp-server" ] || die "databricks-mcp-server not found in $REPO_DIR"

    # Always reinstall from this repo — ensures venv uses custom-ai-dev-kit packages,
    # not stale ones from a previous official install.sh run.
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

# ── Write .mcp.json with Databricks entry ─────────────────────────────────────
MCP_CONFIG="$PROJECT_DIR/.mcp.json"
python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
existing = {}
if path.exists():
    try: existing = json.loads(path.read_text())
    except: pass
ca = '${NODE_EXTRA_CA_CERTS:-}'
env = {'DATABRICKS_CONFIG_PROFILE': '$PROFILE'}
if ca: env['NODE_EXTRA_CA_CERTS'] = ca
existing.setdefault('mcpServers', {})['databricks'] = {
    'command': '$VENV_PYTHON',
    'args':    ['$MCP_ENTRY'],
    'defer_loading': True,
    'env': env
}
path.write_text(json.dumps(existing, indent=2) + '\n')
"
ok "Databricks MCP  →  $MCP_CONFIG"

# =============================================================================
# ── STEP 6: GITHUB MCP ───────────────────────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = false ]; then

step "Step 6 of 9 — GitHub MCP"

# ── Add GitHub entry to .mcp.json ─────────────────────────────────────────────
python3 -c "
import json, pathlib
path = pathlib.Path('$MCP_CONFIG')
data = json.loads(path.read_text())
ca = '${NODE_EXTRA_CA_CERTS:-}'
github_env = {'GITHUB_PERSONAL_ACCESS_TOKEN': ''}
if '$GITHUB_API_URL':
    github_env['GITHUB_API_URL'] = '$GITHUB_API_URL'
if ca: github_env['NODE_EXTRA_CA_CERTS'] = ca
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
        # Run login; ignore non-zero exit from "key already in use" — auth may still succeed
        gh auth login --web --git-protocol ssh 2>&1 || true
        GH_USER=$(gh api user --jq '.login' 2>/dev/null || true)
        if [ -z "$GH_USER" ]; then
            warn "GitHub auth could not be confirmed — token may still work"
        fi
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
    warn "gh CLI unavailable — set GITHUB_PERSONAL_ACCESS_TOKEN manually in .mcp.json"
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
ca = '${NODE_EXTRA_CA_CERTS:-}'
atlassian_entry = {
    'command': 'npx',
    'args':    ['mcp-remote', 'https://mcp.atlassian.com/v1/mcp', '--transport', 'http-first']
}
if ca: atlassian_entry['env'] = {'NODE_EXTRA_CA_CERTS': ca}
data['mcpServers']['atlassian'] = atlassian_entry
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
        # Kill any leftover mcp-remote listener on the OAuth callback port (port 3736)
        # A previous installer run may have left a process holding the port.
        lsof -ti tcp:3736 2>/dev/null | xargs kill -9 2>/dev/null || true
        NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-}" npx mcp-remote https://mcp.atlassian.com/v1/mcp --transport http-first &
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

fi  # end SKILLS_ONLY skip (Steps 6 + 7)

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

    # Helper: interpret git clone/fetch error and print an actionable message
    _skills_clone_error() {
        local err="${1:-}"
        if echo "$err" | grep -qiE "repository not found|permission to .+ denied|403|access denied"; then
            warn "Access denied to enterprise skills repo"
            msg "  Your GitHub account does not have access to: $ENTERPRISE_SKILLS_REPO"
            msg "  Please ask your administrator to grant you access, then re-run:"
            msg "    bash $0 --skills-only"
        elif echo "$err" | grep -qiE "permission denied.*publickey|could not read username|authentication failed"; then
            warn "Authentication failed when cloning enterprise skills repo"
            msg "  Re-run the installer to set up GitHub authentication again, or:"
            msg "    bash $0 --skills-only"
        else
            warn "Failed to clone enterprise skills repo"
            [ -n "$err" ] && msg "  Error: $err"
            msg "  Re-run with --skills-only after resolving the issue"
        fi
    }

    if [ "$ENTERPRISE_SKILLS_MODE" = "git" ]; then
        # ── Git mode: clone / update the remote private repo ──────────────────
        if [ -z "$ENTERPRISE_SKILLS_REPO" ]; then
            warn "ENTERPRISE_SKILLS_MODE=git but ENTERPRISE_SKILLS_REPO is empty — skipping"
        elif [ "$SKILLS_AUTH_MODE" = "skip" ]; then
            warn "Enterprise skills skipped — GitHub authentication not set up"
            msg "  Re-run with:  bash $0 --skills-only  after setting up authentication"
        else
            # Pick clone URL based on auth mode set in Step 2
            SKILLS_CLONE_URL="$ENTERPRISE_SKILLS_REPO"
            [ "$SKILLS_AUTH_MODE" = "https" ] && SKILLS_CLONE_URL="$HTTPS_SKILLS_REPO"

            if [ -d "$ENTERPRISE_SKILLS_REPO_DIR/.git" ]; then
                current_remote=$(git -C "$ENTERPRISE_SKILLS_REPO_DIR" remote get-url origin 2>/dev/null || true)
                if [ "$current_remote" != "$SKILLS_CLONE_URL" ]; then
                    msg "Enterprise skills repo URL changed — re-cloning…"
                    rm -rf "$ENTERPRISE_SKILLS_REPO_DIR"
                    clone_err=$(git clone -q --depth 1 "$SKILLS_CLONE_URL" "$ENTERPRISE_SKILLS_REPO_DIR" 2>&1) \
                        && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                        || _skills_clone_error "$clone_err"
                else
                    fetch_err=$(git -C "$ENTERPRISE_SKILLS_REPO_DIR" fetch -q --depth 1 origin main 2>&1)
                    if [ $? -ne 0 ]; then
                        _skills_clone_error "$fetch_err"
                    else
                        git -C "$ENTERPRISE_SKILLS_REPO_DIR" reset --hard FETCH_HEAD 2>/dev/null \
                            && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                            || warn "Failed to reset enterprise skills repo to latest"
                    fi
                fi
            else
                mkdir -p "$INSTALL_DIR"
                clone_err=$(git clone -q --depth 1 "$SKILLS_CLONE_URL" "$ENTERPRISE_SKILLS_REPO_DIR" 2>&1) \
                    && ENT_SOURCE="$ENTERPRISE_SKILLS_REPO_DIR" \
                    || _skills_clone_error "$clone_err"
            fi
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
        ok "Enterprise skills  ($ENT_COUNT installed)  ->  $SKILLS_DEST"
    else
        warn "No enterprise skills source found — skipping"
    fi
fi

# =============================================================================
# ── STEP 9: WORKSPACE + VERSION LOCK ─────────────────────────────────────────
# =============================================================================

if [ "$SKILLS_ONLY" = false ]; then

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

fi  # end SKILLS_ONLY skip (Step 9)

# =============================================================================
# ── SUMMARY ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
if [ "$SKILLS_ONLY" = true ]; then
    printf "${G}╔════════════════════════════════════════════════════════╗${N}\n"
    printf "${G}║   ✓  Skills Updated                                    ║${N}\n"
    printf "${G}╚════════════════════════════════════════════════════════╝${N}\n"
    echo ""
    printf "  ${B}%-20s${N} %s\n" "Project"           "$PROJECT_DIR"
    printf "  ${B}%-20s${N} %s\n" "Databricks skills" "${DB_COUNT:-0} installed"
    printf "  ${B}%-20s${N} %s\n" "Enterprise skills" "${ENT_COUNT:-0} installed"
    echo ""
    echo "Next steps:"
    printf "  1. Open your project in Claude Code:  ${CY}claude %s${N}\n" "$PROJECT_DIR"
    echo "  2. Skills are active — try: \"List my SQL warehouses\""
else
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
fi
echo ""
