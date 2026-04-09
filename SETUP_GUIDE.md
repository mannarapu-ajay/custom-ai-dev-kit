# McCain Enterprise AI Dev Kit — Setup Guide

This guide walks you through the complete setup process, step by step, including exactly what you will see and what to do at every prompt.

---

## Before You Start

You need two things on your machine before running anything:

- A terminal (macOS/Linux: **Terminal** or **iTerm2** | Windows: **PowerShell**)
- Your **McCain corporate GitHub account** (the one under `@McCainFoods`)

---

## Overview

Setup happens in two stages:

```
Stage 1 — Prerequisites         curl one-liner, no clone needed  (~5 min, one-time)
  ↓
Stage 2 — Enterprise Install    curl one-liner, auto-clones repo  (~10 min, per project)
```

| Stage | Script | Needs clone? | What it does |
|-------|--------|-------------|-------------|
| 1 | `prerequisites.sh` / `prerequisites.ps1` | No — run via curl/irm | Installs Git, GitHub CLI, SSH key, uv, Node.js |
| 2 | `enterprise_install.sh` / `enterprise_install.ps1` | No — auto-clones | Sets up Databricks, MCP servers, enterprise skills |

> Do NOT run the official Databricks `install.sh` — this enterprise installer fully replaces it.

---

## Stage 1 — Prerequisites

The prerequisites script is **fully standalone** — run it directly from GitHub, no clone needed.

### macOS / Linux

```bash
bash <(curl -sL https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/prerequisites.sh)
```

### Windows (PowerShell)

```powershell
irm https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/prerequisites.ps1 | iex
```

---

### What happens inside Prerequisites (3 steps)

---

#### Prerequisites — Step 1 of 3: Git + GitHub Authentication

The script installs Git and the GitHub CLI (`gh`) if not already present, then handles your GitHub identity and SSH key.

**Scenario A — You are already logged into GitHub:**

```
  ✓ Already authenticated with GitHub  (your-username)
  Is 'your-username' your McCain corporate GitHub account? (y/n) [y]:
```

- Type `y` + Enter if this is your McCain GitHub account
- Type `n` + Enter if it's a personal account — the browser will open for you to log in with the right account

**Scenario B — Not authenticated:**

```
  Not authenticated with GitHub — opening browser...
```

- Your browser opens automatically
- Log in with your **McCain corporate GitHub account**
- Authorize the GitHub CLI when prompted
- Return to the terminal when done

---

**Git identity prompt** (always shown):

```
  Full name for git config [First Last]:
  McCain email for git config (e.g. first.last@mccain.ca) [yourname@mccain.ca]:
```

- Type your full name, press Enter
- Type your McCain email address, press Enter
- If the values shown in brackets are already correct, just press Enter to accept them

---

**SSH key setup** — the script generates a dedicated McCain SSH key (`~/.ssh/id_ed25519_mccain`) and registers it on GitHub.

You will then see:

```
  ! ACTION REQUIRED — SAML SSO authorization
    Opening GitHub SSH keys page in your browser...

    In your browser:
      1. Find the key titled:  "McCain Prerequisites Setup - your-machine"
      2. Click:  Configure SSO
      3. Click:  Authorize  "McCainFoods"

    Skip if already authorized or McCainFoods does not enforce SAML SSO.

  Press Enter once you have authorized the key (or to skip) []:
```

- Go to the browser tab that opened (GitHub SSH keys page)
- Find the key listed with your machine name
- Click **Configure SSO** → **Authorize McCainFoods**
- Come back to the terminal and press **Enter**

> If you already authorized this key before, just press Enter to skip.

---

#### Prerequisites — Step 2 of 3: uv (Python package manager)

Fully automatic. You will see either:

```
  ✓ uv already installed  (uv 0.x.x)
```
or:
```
  uv not found — installing...
  ✓ uv installed  (uv 0.x.x)
```

No action needed.

---

#### Prerequisites — Step 3 of 3: Node.js / npx

Fully automatic. You will see either:

```
  ✓ Node.js already installed  (v20.x.x)
  ✓ npx available  (10.x.x)
```
or the installer will install Node.js automatically.

No action needed.

---

#### Prerequisites — Summary

When complete you will see:

```
════════════════════════════════════════════════════════
  Prerequisites installed successfully!
════════════════════════════════════════════════════════

  ✓ Git     git version 2.x.x
  ✓ uv      uv 0.x.x
  ✓ Node    v20.x.x
  ✓ npx     10.x.x
```

**Prerequisites are done. Move to Stage 2.**

---

## Stage 2 — Enterprise Install

Run this from **your project directory** (the folder where you want to work).

The enterprise installer automatically clones the kit repo to `~/.ai-dev-kit/repo` on first run and auto-updates it on every subsequent run — **you never need to `git clone` or `git pull` manually.**

---

### Option A — Run directly from GitHub (recommended)

**macOS / Linux:**
```bash
cd ~/my-project
bash <(curl -sL https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/enterprise_install.sh)
```

**Windows (PowerShell):**
```powershell
cd C:\Users\you\my-project
irm https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/enterprise_install.ps1 | iex
```

> On first run the script clones the kit to `~/.ai-dev-kit/repo` (Mac/Linux) or `%USERPROFILE%\.ai-dev-kit\repo` (Windows). On every subsequent run it silently updates to the latest version.

---

### Option B — Run from a locally cloned repo

If you already have the repo cloned on your machine, the script detects this automatically and uses it directly — no `~/.ai-dev-kit/repo` clone is created.

```bash
# Clone once (anywhere on your machine)
git clone https://github.com/mannarapu-ajay/custom-ai-dev-kit.git
cd custom-ai-dev-kit
```

Then run from your **project directory**:

**macOS / Linux:**
```bash
cd ~/my-project
bash /path/to/custom-ai-dev-kit/enterprise_install.sh
```

**Windows (PowerShell):**
```powershell
cd C:\Users\you\my-project
powershell -ExecutionPolicy Bypass -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1
```

> Both Option A and Option B behave identically — same steps, same output, same result.

---

### Update skills only

Run this whenever new Databricks or enterprise skills are released:

**macOS / Linux:**
```bash
cd ~/my-project
bash <(curl -sL https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/enterprise_install.sh) --skills-only
```

**Windows (PowerShell):**
```powershell
$env:DEVKIT_SKILLS_ONLY="true"; irm https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/enterprise_install.ps1 | iex
```

---

### What happens inside Enterprise Install (8 steps)

---

#### Step 1 of 8 — Project Directory

```
  Project directory [/current/path]:
```

- Press **Enter** to use the current directory (recommended)
- Or type a different path and press Enter

---

#### Step 2 of 8 — Prerequisites

The script verifies everything from Stage 1 is in place. You will see:

```
  ✓ git version 2.x.x
  ✓ uv 0.x.x
  ✓ npx 10.x.x
  ✓ Databricks CLI: x.x.x
  ✓ gh CLI: gh version x.x.x
```

**If any tool is missing**, the script will stop and tell you:

```
  ✗ Missing prerequisites. Run prerequisites first, then re-run this installer.
```

Go back to Stage 1, run prerequisites again, then re-run the enterprise installer.

No action needed if all tools are present.

---

#### Step 3 of 8 — Databricks Workspace & Profile

**Workspace selection — radio menu:**

```
  Choose your Databricks domain / workspace:
  ❯ Growth          https://adb-982288893326755.15.azuredatabricks.net
    Supply Chain    https://adb-1534255211069001.1.azuredatabricks.net
    Finance         https://adb-3107134495216511.11.azuredatabricks.net
    Agriculture     https://adb-54001242538101.1.azuredatabricks.net
    HR              https://adb-2199059861738382.2.azuredatabricks.net
    Procurement     https://adb-360325603937068.8.azuredatabricks.net
    EDP             https://adb-849096460664268.8.azuredatabricks.net
    Enter URL manually
```

- Use **arrow keys** (↑ ↓) to move the selection
- Press **Enter** to confirm
- Choose **Enter URL manually** if your workspace is not listed — you will be prompted to type the URL

---

**Profile selection:**

If you already have Databricks profiles configured (`~/.databrickscfg`):

```
  Choose Databricks profile:
  ❯ DEFAULT
    my-other-profile
    Custom profile name...
```

- Arrow keys + Enter to select an existing profile
- Choose **Custom profile name...** to type a new one

If no profiles exist yet:

```
  No ~/.databrickscfg found — you can authenticate after install.
  Profile name [DEFAULT]:
```

- Press **Enter** to use `DEFAULT`, or type a name and press Enter

---

**Databricks OAuth login** — if not already authenticated:

```
  ! Not authenticated — opening browser for OAuth login…
```

- Browser opens automatically to your Databricks workspace
- Log in and authorize
- Return to the terminal — it continues automatically

---

#### Step 4 of 8 — Authentication + CA Certificates

Fully automatic — verifies your Databricks login and sets up corporate CA certificates so tools work behind the corporate proxy.

```
  ✓ Authenticated as firstname.lastname@mccain.ca
  ✓ Corporate CA certificates configured
```

No action needed.

---

#### Step 5 of 8 — Databricks MCP

Fully automatic — sets up the Databricks MCP server (the bridge between Claude Code and Databricks).

```
  ✓ MCP server ready  →  ~/.ai-dev-kit/.venv
  ✓ Databricks MCP  →  .mcp.json
```

No action needed.

---

#### Step 6 of 8 — Atlassian MCP (Confluence + Jira)

```
  Authenticate with Atlassian now? (y/n) [y]:
```

- Type `y` + Enter to set up Confluence/Jira access now (recommended)
- Type `n` + Enter to skip — it will prompt you automatically the first time you use it in Claude Code

**If you type `y`:**

```
  Starting OAuth flow — a browser window will open.
  Sign in with your Atlassian account, then press Enter here to continue.
```

- Your browser opens to the Atlassian login page
- Sign in with your **McCain Atlassian account** (same email as Jira/Confluence)
- Come back to the terminal
- Press **Enter**

```
  ✓ Atlassian MCP authenticated
```

---

#### Step 7 of 8 — Skills + Settings

Fully automatic — installs Databricks skills and pulls enterprise skills from the private McCainFoods repo.

**Scenario A — Enterprise skills repo is accessible:**

```
  ✓ Enterprise skills repo accessible
  ✓ Databricks skills  (n installed)
  ✓ Enterprise skills  (m installed)
```

---

**Scenario B — SAML SSO not authorized for the skills repo:**

```
  ! SAML SSO authorization required for enterprise skills repo
    Your SSH key needs to be authorized for the McCainFoods org.
    Opening GitHub SSH keys page in your browser...

    In your browser:
      1. Find your SSH key
      2. Click:  Configure SSO
      3. Click:  Authorize "McCainFoods"

  Press Enter once you have authorized the key (or to skip):
```

- Go to your browser, follow the 3 steps
- Come back to the terminal, press **Enter**
- The script will re-test and continue

---

**Scenario C — Your account doesn't have repo access:**

```
  ! Account 'your-username' does not have access to: git@github.com:McCainFoods/...
    Contact your administrator to get access, then re-run:
      bash <(curl -sL .../enterprise_install.sh) --skills-only
```

- Contact your admin to get access to the McCainFoods enterprise skills repo
- Once granted, re-run with `--skills-only` (skips all other steps, just updates skills)

---

#### Step 8 of 8 — Workspace + Version Lock

Fully automatic — creates project scaffolding, updates `.gitignore`, writes metadata.

```
  ✓ .gitignore updated
  ✓ src/generated/README.md
  ✓ instruction-templates/default.md
  ✓ .mccain-adk/metadata.json
  ✓ .mccain-adk/version.lock
```

No action needed.

---

### Enterprise Install — Final Summary

```
╔════════════════════════════════════════════════════════╗
║   ✓  Workspace Ready                                   ║
╚════════════════════════════════════════════════════════╝

  Project              ~/my-project
  Enterprise           McCain
  Workspace            https://adb-xxxx.azuredatabricks.net
  Profile              DEFAULT
  Databricks skills    12 installed
  Enterprise skills    4 installed
  MCP config           .mcp.json

Next steps:
  1. Open your project in Claude Code:  claude ~/my-project
  2. MCP + skills are active — try: "List my SQL warehouses"
```

---

## Quick Reference — Commands

| Task | macOS / Linux | Windows |
|------|--------------|---------|
| Run prerequisites | `bash <(curl -sL .../prerequisites.sh)` | `irm .../prerequisites.ps1 \| iex` |
| Run enterprise install | `bash <(curl -sL .../enterprise_install.sh)` | `irm .../enterprise_install.ps1 \| iex` |
| Update skills only | `bash <(curl -sL .../enterprise_install.sh) --skills-only` | `$env:DEVKIT_SKILLS_ONLY="true"; irm .../enterprise_install.ps1 \| iex` |
| Force full reinstall | `bash <(curl -sL .../enterprise_install.sh) --force` | `$env:DEVKIT_FORCE="true"; irm .../enterprise_install.ps1 \| iex` |
| Use a specific profile | `bash <(curl -sL .../enterprise_install.sh) --profile NAME` | `$env:DEVKIT_PROFILE="NAME"; irm .../enterprise_install.ps1 \| iex` |
| Run from local clone (Mac/Linux) | `bash enterprise_install.sh` | — |
| Run from local clone (Windows) | — | `.\enterprise_install.ps1` |

> Replace `...` with `https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main`

---

## Troubleshooting

**"git not found" or "uv not found" when running enterprise install**
→ Run prerequisites first, then re-run the enterprise installer.

**"Could not auto-register SSH key"**
→ Go to https://github.com/settings/keys and add the public key manually.
→ The script will print the public key content for you to copy.

**"SAML SSO authorization required"**
→ The browser will open automatically. Find your SSH key → Configure SSO → Authorize McCainFoods.

**"Account does not have access to enterprise skills repo"**
→ Contact your administrator to get access, then re-run with `--skills-only`.

**"Databricks CLI install failed"**
→ Install manually: https://docs.databricks.com/dev-tools/cli/install.html then re-run.

**uv or Node not found after prerequisites**
→ Close your terminal, open a new one (PATH needs to reload), then re-run the enterprise installer.

**"Failed to clone enterprise kit"** (curl/irm mode only)
→ Run prerequisites first to ensure git is installed, then re-run.
→ Check your internet connection and that github.com is reachable.

**Enterprise install on Windows fails at irm | iex**
→ Use env vars to pass flags: `$env:DEVKIT_SKILLS_ONLY="true"` before `irm ... | iex`.
→ Flags like `-SkillsOnly` only work when running from a local file (Option B).
