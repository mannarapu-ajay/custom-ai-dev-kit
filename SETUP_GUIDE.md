# McCain Enterprise AI Dev Kit — Setup Guide

Complete step-by-step guide covering every prompt and what to do at each one.

---

## Before You Start

You need two things before running anything:

- A terminal (macOS/Linux: **Terminal** or **iTerm2** | Windows: **PowerShell**)
- Your **McCain corporate GitHub account** (the one under `@McCainFoods`)

---

## Overview

```
Stage 1 — Prerequisites         run via curl/irm, no clone needed   (~5 min, one-time)
  ↓
Stage 2 — Enterprise Install    run via curl/irm, auto-clones repo   (~10 min, per project)
```

| Stage | Script | What it does |
|-------|--------|-------------|
| 1 | `prerequisites.sh` / `prerequisites.ps1` | Git, GitHub CLI, SSH key, uv, Node.js |
| 2 | `enterprise_install.sh` / `enterprise_install.ps1` | Databricks, MCP servers, enterprise skills |

> Do **not** run the official Databricks `install.sh` — the enterprise installer fully replaces it.

---

## Stage 1 — Prerequisites

Run once per machine. No clone needed — runs directly from GitHub.

**macOS / Linux:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/prerequisites.sh)
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main/prerequisites.ps1 | iex
```

---

### Prerequisites — Step 1 of 3: Git + GitHub Authentication

Installs Git and the GitHub CLI (`gh`), then handles your GitHub identity and SSH key.

**Scenario A — Already logged in:**
```
  ✓ Already authenticated with GitHub  (your-username)
  Is 'your-username' your McCain corporate GitHub account? (y/n) [y]:
```
- Press **Enter** (or `y`) if this is your McCain account
- Type `n` if it's a personal account — browser opens for you to log in with the right account

**Scenario B — Not logged in:**
```
  Not authenticated with GitHub — opening browser...
```
- Browser opens automatically — log in with your **McCain corporate GitHub account**
- Authorize the GitHub CLI, then return to the terminal

---

**Git identity:**
```
  Full name for git config [First Last]:
  McCain email for git config (e.g. first.last@mccain.ca) [yourname@mccain.ca]:
```
Press Enter to accept if the values shown are correct, otherwise type the correct values.

---

**SSH key + SAML SSO:**

The script generates `~/.ssh/id_ed25519_mccain` and registers it on GitHub. You will then see:

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
- In the browser tab that opened: find the key → **Configure SSO** → **Authorize McCainFoods**
- Return to terminal, press **Enter**

> If you already authorized this key before, just press Enter to skip.

---

### Prerequisites — Step 2 of 3: uv

Fully automatic:
```
  ✓ uv already installed  (uv 0.x.x)
```
or installs it silently. No action needed.

---

### Prerequisites — Step 3 of 3: Node.js / npx

Fully automatic. No action needed.

---

### Prerequisites — Done

```
════════════════════════════════════════════════════════
  Prerequisites installed successfully!
════════════════════════════════════════════════════════

  ✓ Git     git version 2.x.x
  ✓ uv      uv 0.x.x
  ✓ Node    v20.x.x
  ✓ npx     10.x.x
```

**Move to Stage 2.**

---

## Stage 2 — Enterprise Install

Run from **your project directory** (the folder where you want to work).

The installer auto-clones the kit repo to `~/.ai-dev-kit/repo` on first run and silently updates it on every subsequent run — **no manual `git clone` needed.**

---

### Option A — Run from GitHub (recommended)

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

---

### Option B — Run from a local clone

```bash
git clone https://github.com/mannarapu-ajay/custom-ai-dev-kit.git
```

**macOS / Linux:**
```bash
cd ~/my-project
bash /path/to/custom-ai-dev-kit/enterprise_install.sh
```

**Windows:**
```powershell
cd C:\Users\you\my-project
powershell -ExecutionPolicy Bypass -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1
```

Both options behave identically — same steps, same result.

---

### Common flags

| Task | macOS / Linux | Windows |
|------|--------------|---------|
| Update skills only | `... enterprise_install.sh --skills-only` | `$env:DEVKIT_SKILLS_ONLY="true"; irm ... \| iex` |
| Force full reinstall | `... enterprise_install.sh --force` | `$env:DEVKIT_FORCE="true"; irm ... \| iex` |
| Specify profile | `... enterprise_install.sh --profile NAME` | `$env:DEVKIT_PROFILE="NAME"; irm ... \| iex` |
| Local file (Windows) | — | `.\enterprise_install.ps1 -SkillsOnly` |

> Replace `...` with `bash <(curl -sL https://raw.githubusercontent.com/mannarapu-ajay/custom-ai-dev-kit/main`

---

### What happens inside Enterprise Install (8 steps)

---

#### Step 1 of 8 — Project Directory

```
  Project directory [/current/path]:
```
Press **Enter** to use the current directory (recommended), or type a different path.

---

#### Step 2 of 8 — Prerequisites

Verifies everything from Stage 1 is in place:

```
  ✓ git version 2.x.x
  ✓ gh CLI: gh version x.x.x
  ✓ Databricks CLI: x.x.x
  ✓ uv 0.x.x
  ✓ npx 10.x.x
```

If any tool is missing the script stops with a specific error. Go back to Stage 1, run prerequisites, then re-run.

---

#### Step 3 of 8 — Databricks Workspace & Profile

**Workspace selection (arrow keys + Enter):**
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
Choose **Enter URL manually** if your workspace isn't listed.

---

**Profile selection:**
```
  Choose Databricks profile:
  ❯ DEFAULT
    my-other-profile
    Custom profile name...
```
Choose **Custom profile name...** to enter a new one. If no `~/.databrickscfg` exists yet:
```
  No ~/.databrickscfg found — you can authenticate after install.
  Profile name [DEFAULT]:
```

---

**Databricks OAuth** (if not already authenticated):
```
  ! Not authenticated — opening browser for OAuth login…
```
Browser opens to your workspace — log in and authorize, then return to terminal.

---

#### Step 4 of 8 — Authentication + CA Certificates

Fully automatic — verifies Databricks login and sets up corporate CA certificates.

```
  ✓ Authenticated as firstname.lastname@mccain.ca
  ✓ Corporate CA certificates configured
```

No action needed.

---

#### Step 5 of 8 — Databricks MCP

Fully automatic — clones/updates the kit repo and sets up the Databricks MCP server.

```
  ✓ Repository cloned  (main)
  ✓ MCP server ready
  ✓ Databricks MCP  →  .mcp.json
```

No action needed.

---

#### Step 6 of 8 — Atlassian MCP (Confluence + Jira)

```
  Authenticate with Atlassian now? (y/n) [y]:
```
- `y` — set up Confluence/Jira access now (recommended)
- `n` — skip; OAuth will prompt automatically on first use in Claude Code

**If you type `y`:**
```
  Starting OAuth flow — a browser window will open.
  Sign in with your Atlassian account, then press Enter here to continue.
```
- Browser opens to Atlassian login — sign in with your **McCain Atlassian account**
- Return to terminal, press **Enter**

```
  ✓ Atlassian MCP authenticated
```

> If no browser opens, your OAuth token is already cached from a previous run. Just press Enter.

---

#### Step 7 of 8 — Skills + Settings

Fully automatic — installs Databricks skills and enterprise skills from the McCainFoods private repo.

**Scenario A — All good:**
```
  ✓ Enterprise skills repo accessible
  ✓ Databricks skills  (n installed)
  ✓ Enterprise skills  (m installed)
  ✓ .claude/settings.json
```

**Scenario B — SAML SSO not yet authorized for the skills repo:**
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
Follow the 3 browser steps, then press **Enter**. The script re-tests and continues.

**Scenario C — No repo access:**
```
  ! Account 'your-username' does not have access to: git@github.com:McCainFoods/...
    Contact your administrator to get access, then re-run:
      bash <(curl -sL .../enterprise_install.sh) --skills-only
```
Get access from your admin, then re-run with `--skills-only`.

---

#### Step 8 of 8 — Workspace

Fully automatic — writes `.ai-dev-kit/` state files and updates `.gitignore`.

```
  ✓ .ai-dev-kit/version  (0.1.7)
  ✓ .ai-dev-kit/.installed-skills
  ✓ .ai-dev-kit/.skills-profile
  ✓ .gitignore updated
```

No action needed.

---

### Final project structure

After install your project directory contains:

```
my-project/
├── .ai-dev-kit/
│   ├── version               ← enterprise kit version
│   ├── .installed-skills     ← manifest of installed skills
│   └── .skills-profile       ← "enterprise"
├── .claude/
│   ├── skills/               ← databricks + enterprise skills
│   └── settings.json         ← auto-update hook
├── .mcp.json                 ← Databricks + Atlassian MCP config
└── .gitignore                ← ignores all of the above
```

---

### Final Summary screen

```
╔════════════════════════════════════════════════════════╗
║   ✓  Workspace Ready                                   ║
╚════════════════════════════════════════════════════════╝

  Project              ~/my-project
  Enterprise           McCain
  Workspace            https://adb-xxxx.azuredatabricks.net
  Profile              DEFAULT
  Databricks skills    n installed
  Enterprise skills    m installed
  MCP config           .mcp.json

Next steps:
  1. Open your project in Claude Code:  claude ~/my-project
  2. MCP + skills are active — try: "List my SQL warehouses"
```

---

## Troubleshooting

**"git not found" / "uv not found" when running enterprise install**
→ Run Stage 1 prerequisites first, open a new terminal, then re-run.

**"Could not auto-register SSH key"**
→ Go to https://github.com/settings/keys and add the public key manually (the script prints it for you).

**"SAML SSO authorization required"**
→ Browser opens automatically. Find your SSH key → Configure SSO → Authorize McCainFoods.

**"Account does not have access to enterprise skills repo"**
→ Contact your admin for access, then re-run with `--skills-only`.

**"Databricks CLI install failed"**
→ Install manually: https://docs.databricks.com/dev-tools/cli/install.html then re-run.

**uv or Node not found after prerequisites**
→ Close terminal, open a new one (PATH needs to reload), then re-run.

**"Failed to clone enterprise kit"** (curl/irm mode)
→ Check internet and that github.com is reachable. Ensure git is installed (run prerequisites).

**Enterprise install on Windows fails at `irm | iex`**
→ Use env vars for flags: `$env:DEVKIT_SKILLS_ONLY="true"` before `irm ... | iex`.
→ Or use Option B (local clone) and run `.\enterprise_install.ps1 -SkillsOnly` directly.

**Atlassian browser doesn't open**
→ OAuth token is already cached from a previous run. Press Enter to continue — it will work on first Claude Code use.
