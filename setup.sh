#!/usr/bin/env bash
#
# McCain Enterprise Dev Environment Setup
#
# Checks and installs the following prerequisites:
#   1. Git  — with McCain GitHub authentication, SSH key generation, and SAML SSO
#   2. uv   — Python package / project manager (astral.sh)
#   3. Node.js / npx
#
# Usage:
#   bash setup.sh
#

set -euo pipefail

# =============================================================================
# ── CONFIGURATION ─────────────────────────────────────────────────────────────
# =============================================================================

ENTERPRISE_ORG="McCainFoods"
MCCAIN_SSH_KEY="$HOME/.ssh/id_ed25519_mccain"

# =============================================================================
# ── OUTPUT HELPERS ────────────────────────────────────────────────────────────
# =============================================================================

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[1m'; CY='\033[0;36m'; N='\033[0m'

msg()  { echo -e "  $*"; }
ok()   { echo -e "  ${G}✓${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
die()  { echo -e "  ${R}✗${N} $*" >&2; exit 1; }
step() { echo -e "\n${CY}────────────────────────────────────────────────────────${N}\n  ${B}$*${N}\n${CY}────────────────────────────────────────────────────────${N}\n"; }

prompt() {
    local text="$1" default="${2:-}" result=""
    printf "  %b [%s]: " "$text" "$default" > /dev/tty
    read -r result < /dev/tty
    [ -z "$result" ] && echo "$default" || echo "$result"
}

# =============================================================================
# ── PLATFORM CHECK ────────────────────────────────────────────────────────────
# =============================================================================

OS="$(uname -s)"
if [ "$OS" != "Darwin" ] && [ "$OS" != "Linux" ]; then
    die "Unsupported OS: $OS. This script supports macOS and Linux only."
fi

# =============================================================================
# ── HOMEBREW (macOS package manager) ─────────────────────────────────────────
# =============================================================================

_ensure_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        msg "Homebrew not found — installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/tty
        # Add brew to PATH for the remainder of this session
        if [ -f "/opt/homebrew/bin/brew" ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [ -f "/usr/local/bin/brew" ]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        ok "Homebrew installed"
    fi
}

# =============================================================================
# ── STEP 1: GIT ───────────────────────────────────────────────────────────────
# =============================================================================

step "Step 1 of 3 — Git"

if command -v git >/dev/null 2>&1; then
    ok "Git already installed  ($(git --version))"
else
    msg "Git not found — installing..."
    if [ "$OS" = "Darwin" ]; then
        _ensure_brew
        brew install git
    else
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update -qq && sudo apt-get install -y git
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y git
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y git
        else
            die "Could not determine package manager. Install git manually and re-run."
        fi
    fi
    ok "Git installed  ($(git --version))"
fi

# ── GitHub CLI (gh) — required for auth and SSH key registration ──────────────

if ! command -v gh >/dev/null 2>&1; then
    msg "GitHub CLI (gh) not found — installing..."
    if [ "$OS" = "Darwin" ]; then
        _ensure_brew
        brew install gh
    else
        if command -v apt-get >/dev/null 2>&1; then
            curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
            sudo apt-get update -qq && sudo apt-get install -y gh
        else
            die "Install GitHub CLI manually (https://cli.github.com) and re-run."
        fi
    fi
    ok "GitHub CLI installed  ($(gh --version | head -1))"
else
    ok "GitHub CLI already installed  ($(gh --version | head -1))"
fi

# ── Git global config (name / email) ─────────────────────────────────────────

_configure_git_identity() {
    local current_name current_email

    current_name=$(git config --global user.name 2>/dev/null || true)
    current_email=$(git config --global user.email 2>/dev/null || true)

    # Pull from gh if available and not yet set
    if [ -z "$current_name" ] || [ -z "$current_email" ]; then
        local gh_name gh_email
        gh_name=$(gh api user --jq '.name' 2>/dev/null || true)
        gh_email=$(gh api user --jq '.email' 2>/dev/null || true)
        [ -z "$current_name" ] && current_name="${gh_name:-}"
        [ -z "$current_email" ] && current_email="${gh_email:-}"
    fi

    local name email
    name=$(prompt "Full name for git config" "${current_name:-First Last}")
    email=$(prompt "McCain email for git config (e.g. first.last@mccain.ca)" "${current_email:-yourname@mccain.ca}")

    git config --global user.name  "$name"
    git config --global user.email "$email"
    git config --global push.default current
    git config --global pull.rebase true
    git config --global init.defaultBranch main
    git config --global core.autocrlf input

    ok "Git identity configured  ($name <$email>)"
}

# ── SSH key helper ────────────────────────────────────────────────────────────

_ssh_check() {
    ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 || true
}

_setup_mccain_ssh_key() {
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

    # 1. Generate key (skip if already exists)
    if [ ! -f "$MCCAIN_SSH_KEY" ]; then
        msg "Generating McCain SSH key (ed25519)..."
        local git_email
        git_email=$(gh api user --jq '.email' 2>/dev/null || git config --global user.email 2>/dev/null || echo "mccain-setup")
        ssh-keygen -t ed25519 -C "$git_email" -f "$MCCAIN_SSH_KEY" -N "" < /dev/tty
        ok "SSH key generated: $MCCAIN_SSH_KEY"
    else
        ok "Existing McCain SSH key found — reusing  ($MCCAIN_SSH_KEY)"
    fi

    # 2. Register on GitHub (skip if fingerprint already present)
    local local_fp
    local_fp=$(ssh-keygen -lf "${MCCAIN_SSH_KEY}.pub" 2>/dev/null | awk '{print $2}') || true
    if [ -n "$local_fp" ] && gh ssh-key list 2>/dev/null | grep -q "$local_fp"; then
        ok "SSH key already registered on GitHub"
    else
        local host_label="McCain Enterprise Setup - $(hostname)"
        msg "Registering SSH key on GitHub..."
        local add_err=""
        if gh ssh-key add "${MCCAIN_SSH_KEY}.pub" --title "$host_label" 2>/dev/null; then
            ok "SSH key registered on GitHub  ($host_label)"

            echo ""
            warn "ACTION REQUIRED — SAML SSO authorization"
            msg "  Opening GitHub SSH keys page in your browser..."
            if command -v open >/dev/null 2>&1; then
                open "https://github.com/settings/keys" 2>/dev/null || true
            elif command -v xdg-open >/dev/null 2>&1; then
                xdg-open "https://github.com/settings/keys" 2>/dev/null || true
            else
                msg "  Manually open: https://github.com/settings/keys"
            fi
            echo ""
            msg "  In your browser:"
            msg "    1. Find key:  \"$host_label\""
            msg "    2. Click:     Configure SSO"
            msg "    3. Click:     Authorize  \"${ENTERPRISE_ORG}\""
            echo ""
            msg "  Skip if ${ENTERPRISE_ORG} does not enforce SAML SSO."
            echo ""
            prompt "Press Enter once you have authorized the key (or to skip)" "" > /dev/null
        else
            warn "Could not auto-register SSH key — add it manually at https://github.com/settings/keys"
            msg "  Public key:"
            msg "  $(cat "${MCCAIN_SSH_KEY}.pub")"
        fi
    fi

    # 3. Update ~/.ssh/config to always use this key for github.com
    local ssh_config="$HOME/.ssh/config"
    touch "$ssh_config" && chmod 600 "$ssh_config"
    if ! grep -q "Host github.com" "$ssh_config" 2>/dev/null; then
        printf '\nHost github.com\n  IdentityFile %s\n  IdentitiesOnly yes\n' "$MCCAIN_SSH_KEY" >> "$ssh_config"
    else
        # Replace the IdentityFile line inside the github.com block
        python3 -c "
import re, pathlib
cfg = pathlib.Path('$ssh_config')
content = cfg.read_text()
block = '\nHost github.com\n  IdentityFile $MCCAIN_SSH_KEY\n  IdentitiesOnly yes\n'
new = re.sub(r'\nHost github\.com\n(?:[ \t]+[^\n]*\n)*', block, content)
cfg.write_text(new if new != content else content)
" 2>/dev/null || true
    fi
    ok "~/.ssh/config updated to use McCain key for github.com"

    # 4. Load key into ssh-agent for this session
    eval "$(ssh-agent -s)" 2>/dev/null || true
    ssh-add "$MCCAIN_SSH_KEY" 2>/dev/null || true
}

# ── Main GitHub authentication flow ──────────────────────────────────────────

_authenticate_github() {
    local ssh_out gh_user

    ssh_out=$(_ssh_check)

    if echo "$ssh_out" | grep -q "Hi "; then
        gh_user=$(echo "$ssh_out" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
        ok "Already authenticated with GitHub  (${gh_user:-unknown})"

        # Confirm this is the correct McCain corporate account
        local confirm
        confirm=$(prompt "Is '${gh_user:-unknown}' your McCain corporate GitHub account? (y/n)" "y")
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            _configure_git_identity
            _setup_mccain_ssh_key
            return
        fi

        msg "Re-authenticating with your McCain account..."
    else
        msg "Not authenticated with GitHub — opening browser..."
    fi

    gh auth login --web --git-protocol https --scopes admin:public_key < /dev/tty || true
    gh auth setup-git 2>/dev/null || true

    _configure_git_identity
    _setup_mccain_ssh_key

    # Verify SSH after setup
    msg "Verifying SSH access..."
    ssh_out=$(_ssh_check)
    if echo "$ssh_out" | grep -q "Hi "; then
        gh_user=$(echo "$ssh_out" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p')
        ok "SSH access to github.com confirmed  (authenticated as: ${gh_user:-unknown})"
    else
        warn "SSH access could not be verified — you may need to add the key manually."
        msg "  Public key: $(cat "${MCCAIN_SSH_KEY}.pub" 2>/dev/null || echo 'Key not found')"
        msg "  Go to: https://github.com/settings/keys"
    fi
}

_authenticate_github

# =============================================================================
# ── STEP 2: UV ────────────────────────────────────────────────────────────────
# =============================================================================

step "Step 2 of 3 — uv (Python package manager)"

if command -v uv >/dev/null 2>&1; then
    ok "uv already installed  ($(uv --version))"
else
    msg "uv not found — installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add uv to PATH for this session
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    if command -v uv >/dev/null 2>&1; then
        ok "uv installed  ($(uv --version))"
    else
        warn "uv installed but not in current PATH. Restart your terminal or add to PATH:"
        msg "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# =============================================================================
# ── STEP 3: NODE.JS / NPX ─────────────────────────────────────────────────────
# =============================================================================

step "Step 3 of 3 — Node.js / npx"

if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
    ok "Node.js already installed  ($(node --version))"
    ok "npx available  ($(npx --version))"
else
    msg "Node.js not found — installing..."
    if [ "$OS" = "Darwin" ]; then
        _ensure_brew
        brew install node
    else
        # Use NodeSource LTS for Linux
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - 2>/dev/null \
            || die "Failed to set up NodeSource repo. Install Node.js manually: https://nodejs.org"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y nodejs
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y nodejs npm
        else
            die "Install Node.js manually from https://nodejs.org and re-run."
        fi
    fi
    ok "Node.js installed  ($(node --version))"
    ok "npx available  ($(npx --version))"
fi

# =============================================================================
# ── SUMMARY ───────────────────────────────────────────────────────────────────
# =============================================================================

echo ""
echo -e "${CY}════════════════════════════════════════════════════════${N}"
echo -e "  ${G}${B}Setup complete!${N}"
echo -e "${CY}════════════════════════════════════════════════════════${N}"
echo ""
echo -e "  ${G}✓${N} Git     $(git --version 2>/dev/null || echo 'see above')"
echo -e "  ${G}✓${N} uv      $(uv --version 2>/dev/null || echo 'restart terminal to activate')"
echo -e "  ${G}✓${N} Node    $(node --version 2>/dev/null || echo 'see above')"
echo -e "  ${G}✓${N} npx     $(npx --version 2>/dev/null || echo 'see above')"
echo ""
echo -e "  ${Y}Note:${N} If uv or Node are not found in a new terminal, add to your shell profile:"
echo -e "        export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
