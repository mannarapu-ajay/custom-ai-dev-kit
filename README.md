# Databricks AI Dev Kit

<p align="center">
  <img src="https://img.shields.io/badge/Databricks-Certified%20Gold%20Project-FFD700?style=for-the-badge&logo=databricks&logoColor=black" alt="Databricks Certified Gold Project">
</p>

---
> 🔒 Proactive Dependency Security  
> As part of our commitment to supply chain integrity, we continually monitor our dependency tree against known vulnerabilities and industry advisories. In response to a recently disclosed supply chain incident affecting litellm versions 1.82.7–1.82.8, we have audited our packages and removed the litellm dependency for most usage. It is solely used in the test directory for skills evaluation and optimization, and has been pinned to a safe version.  
> For full third-party attribution, see NOTICE.txt.
---

## Enterprise Installation (McCain)

The enterprise installer extends the standard AI Dev Kit with:
- Automated workspace selection (Growth, Supply Chain, Finance, Agriculture, HR, Procurement, EDP)
- Dedicated McCain SSH key (`~/.ssh/id_ed25519_mccain`) — created once, reused across all projects
- GitHub account verification (ensures you're using your McCain corporate account)
- Enterprise skills pulled automatically from the private McCain skills repo
- Corporate CA certificate configuration
- GitHub MCP + Atlassian MCP (Confluence + Jira) setup

### Prerequisites

- **gh CLI** — [https://cli.github.com](https://cli.github.com)
- **git**, **Node.js**, **uv**, **Databricks CLI** (auto-installed if missing)
- Access to the McCain GitHub org

### Mac / Linux

```bash
# Full install (first time)
bash /path/to/custom-ai-dev-kit/enterprise_install.sh

# Skills only — re-pull enterprise skills without touching MCP or workspace config
bash /path/to/custom-ai-dev-kit/enterprise_install.sh --skills-only

# Specify Databricks profile
bash /path/to/custom-ai-dev-kit/enterprise_install.sh --profile DEFAULT
```

### Windows (PowerShell)

```powershell
# Full install (first time)
powershell -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1

# Skills only — re-pull enterprise skills without touching MCP or workspace config
powershell -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1 -SkillsOnly

# Specify Databricks profile
powershell -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1 -Profile DEFAULT
```

### What each step does

| Step | Description | Skipped by `--skills-only` |
|------|-------------|---------------------------|
| 1 — Project Directory | Create project folder and `.claude/skills` | |
| 2 — Prerequisites | Install git, Node.js, uv, Databricks CLI, gh CLI; set up McCain SSH key | Tool checks only |
| 3 — Databricks Workspace | Select workspace URL and Databricks profile | ✓ |
| 4 — Authentication + CA | Verify Databricks auth; configure corporate CA certs | ✓ |
| 5 — Databricks MCP | Install and configure the Databricks MCP server | ✓ |
| 6 — GitHub MCP | Configure GitHub MCP with OAuth token | ✓ |
| 7 — Atlassian MCP | Configure Atlassian MCP (Confluence + Jira) | ✓ |
| 8 — Skills + Settings | Install Databricks and enterprise skills | |
| 9 — Version Lock | Write `.gitignore`, metadata, and `version.lock` | ✓ |

### SSH key setup

On first run the installer:
1. Checks if you already have SSH access to `github.com`
2. If yes — confirms the authenticated account is your McCain corporate account
3. If no (or wrong account) — opens the browser for `gh auth login`
4. Creates `~/.ssh/id_ed25519_mccain` (only if it doesn't already exist)
5. Registers the key on your McCain GitHub account
6. Updates `~/.ssh/config` so all `github.com` connections use this key

The key is reused across all projects — the installer will detect it on subsequent runs and skip generation.

### Troubleshooting

**`gh ssh-key list` returns HTTP 404**
Your `gh` session is missing the `admin:public_key` scope. Re-run the installer — it will re-authenticate with the correct scopes automatically.

**Enterprise skills cloned but skills count is 0**
Check `ENTERPRISE_SKILLS_REPO_SUBPATH` in `enterprise_install.sh` — it must match the subfolder inside the repo where `SKILL.md` files live.

**Access denied to enterprise skills repo**
Your GitHub account does not have access. Contact your administrator, then re-run with `--skills-only` once access is granted.

---

## Overview

AI-Driven Development (vibe coding) on Databricks just got a whole lot better. The **AI Dev Kit** gives your AI coding assistant (Claude Code, Cursor, Antigravity, Windsurf, etc.) the trusted sources it needs to build faster and smarter on Databricks.

<p align="center">
  <img src="databricks-tools-core/docs/architecture.svg" alt="Architecture" width="700">
</p>

---

## What Can I Build?

- **Spark Declarative Pipelines** (streaming tables, CDC, SCD Type 2, Auto Loader)
- **Databricks Jobs** (scheduled workflows, multi-task DAGs)
- **AI/BI Dashboards** (visualizations, KPIs, analytics)
- **Unity Catalog** (tables, volumes, governance)
- **Genie Spaces** (natural language data exploration)
- **Knowledge Assistants** (RAG-based document Q&A)
- **MLflow Experiments** (evaluation, scoring, traces)
- **Model Serving** (deploy ML models and AI agents to endpoints)
- **Databricks Apps** (full-stack web applications with foundation model integration)
- ...and more

---

## Choose Your Own Adventure

| Adventure                        | Best For | Start Here |
|----------------------------------|----------|------------|
| :star: [**Install AI Dev Kit**](#install-in-existing-project) | **Start here!** Follow quick install instructions to add to your existing project folder | [Quick Start (install)](#install-in-existing-project)
| [**Visual Builder App**](#visual-builder-app) | Web-based UI for Databricks development | `databricks-builder-app/` |
| [**Core Library**](#core-library) | Building custom integrations (LangChain, OpenAI, etc.) | `pip install` |
| [**Skills Only**](databricks-skills/) | Provide Databricks patterns and best practices (without MCP functions) | Install skills |
| [**Genie Code Skills**](databricks-skills/install_skills_to_genie_code.sh) | Install Databricks skills for Genie Code to reference | [Genie Code skills (install)](#genie-code-skills) |
| [**MCP Tools Only**](databricks-mcp-server/) | Just executable actions (no guidance) | Register MCP server |
---

## Quick Start

### Prerequisites

- [uv](https://github.com/astral-sh/uv) - Python package manager
- [Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/) - Command line interface for Databricks
- AI coding environment (one or more):
  - [Claude Code](https://claude.ai/code)
  - [Cursor](https://cursor.com)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli)
  - [Antigravity](https://antigravity.google)


### Install in existing project
By default this will install at a project level rather than a user level. This is often a good fit, but requires you to run your client from the exact directory that was used for the install.
_Note: Project configuration files can be re-used in other projects. You find these configs under .claude, .cursor, .gemini, or .agents_

#### Mac / Linux

**Basic installation** (uses DEFAULT profile, project scope)

```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh)
```

<details>
<summary><strong>Advanced Options</strong> (click to expand)</summary>

**Global installation with force reinstall**

```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) --global --force
```

**Specify profile and force reinstall**

```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) --profile DEFAULT --force
```

**Install for specific tools only**

```bash
bash <(curl -sL https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.sh) --tools cursor,gemini,antigravity
```

</details>

**Next steps:** Respond to interactive prompts and follow the on-screen instructions.
- Note: Cursor and Copilot require updating settings manually after install.

#### Windows (PowerShell)

**Basic installation** (uses DEFAULT profile, project scope)

```powershell
irm https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.ps1 | iex
```

<details>
<summary><strong>Advanced Options</strong> (click to expand)</summary>

**Download script first**

```powershell
irm https://raw.githubusercontent.com/databricks-solutions/ai-dev-kit/main/install.ps1 -OutFile install.ps1
```

**Global installation with force reinstall**

```powershell
.\install.ps1 -Global -Force
```

**Specify profile and force reinstall**

```powershell
.\install.ps1 -Profile DEFAULT -Force
```

**Install for specific tools only**

```powershell
.\install.ps1 -Tools cursor,gemini,antigravity
```

</details>

**Next steps:** Respond to interactive prompts and follow the on-screen instructions.
- Note: Cursor and Copilot require updating settings manually after install.


### Visual Builder App

Full-stack web application with chat UI for Databricks development:

```bash
cd ai-dev-kit/databricks-builder-app
./scripts/setup.sh
# Follow instructions to start the app
```


### Core Library

Use `databricks-tools-core` directly in your Python projects:

```python
from databricks_tools_core.sql import execute_sql

results = execute_sql("SELECT * FROM my_catalog.schema.table LIMIT 10")
```

Works with LangChain, OpenAI Agents SDK, or any Python framework. See [databricks-tools-core/](databricks-tools-core/) for details.

---
## Genie Code Skills
  
  Will install and deploy all available skills to your personal skills directory for all Genie Code sessions to reference while planning/building anything directly in the UI. No post-install steps as workspace is automatically configured during install process for Genie Code to use the skills.

  **Basic installation** (uses DEFAULT profile)

```bash
#Execute from root folder (/ai-dev-kit)
./databricks-skills/install_skills_to_genie_code.sh
```

**Advance installation** (uses provided profile)

```bash
#Execute from root folder (/ai-dev-kit)
./databricks-skills/install_skills_to_genie_code <profile_name>
```

**Skill modification or Custom Skill**

After the script successfully installs the skills to your workspace, you may find the skills under `/Workspace/Users/<your_user_name>/.assistant/skills`.

This directory is customizable if you wish to only use certain skills or even create custom skills that are related to your organization to make Genie Code even better.  You can modify/remove existing skills or create new skills folders that Genie Code will automatically use in any session.

## What's Included

| Component | Description |
|-----------|-------------|
| [`databricks-tools-core/`](databricks-tools-core/) | Python library with high-level Databricks functions |
| [`databricks-mcp-server/`](databricks-mcp-server/) | MCP server exposing 50+ tools for AI assistants |
| [`databricks-skills/`](databricks-skills/) | 20 markdown skills teaching Databricks patterns |
| [`databricks-builder-app/`](databricks-builder-app/) | Full-stack web app with Claude Code integration |

---

## Star History

<a href="https://star-history.com/#databricks-solutions/ai-dev-kit&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=databricks-solutions/ai-dev-kit&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=databricks-solutions/ai-dev-kit&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=databricks-solutions/ai-dev-kit&type=Date" />
 </picture>
</a>

---

## License

(c) 2026 Databricks, Inc. All rights reserved.

The source in this project is provided subject to the [Databricks License](https://databricks.com/db-license-source). See [LICENSE.md](LICENSE.md) for details.

<details>
<summary><strong>Third-Party Licenses</strong></summary>

| Package | Version | License | Project URL |
|---------|---------|---------|-------------|
| [fastmcp](https://github.com/jlowin/fastmcp) | ≥0.1.0 | MIT | https://github.com/jlowin/fastmcp |
| [mcp](https://github.com/modelcontextprotocol/python-sdk) | ≥1.0.0 | MIT | https://github.com/modelcontextprotocol/python-sdk |
| [sqlglot](https://github.com/tobymao/sqlglot) | ≥20.0.0 | MIT | https://github.com/tobymao/sqlglot |
| [sqlfluff](https://github.com/sqlfluff/sqlfluff) | ≥3.0.0 | MIT | https://github.com/sqlfluff/sqlfluff |
| [plutoprint](https://github.com/nicvagn/plutoprint) | ==0.19.0 | MIT | https://github.com/plutoprint/plutoprint |
| [claude-agent-sdk](https://github.com/anthropics/claude-code) | ≥0.1.19 | MIT | https://github.com/anthropics/claude-code |
| [fastapi](https://github.com/fastapi/fastapi) | ≥0.115.8 | MIT | https://github.com/fastapi/fastapi |
| [uvicorn](https://github.com/encode/uvicorn) | ≥0.34.0 | BSD-3-Clause | https://github.com/encode/uvicorn |
| [httpx](https://github.com/encode/httpx) | ≥0.28.0 | BSD-3-Clause | https://github.com/encode/httpx |
| [sqlalchemy](https://github.com/sqlalchemy/sqlalchemy) | ≥2.0.41 | MIT | https://github.com/sqlalchemy/sqlalchemy |
| [alembic](https://github.com/sqlalchemy/alembic) | ≥1.16.1 | MIT | https://github.com/sqlalchemy/alembic |
| [asyncpg](https://github.com/MagicStack/asyncpg) | ≥0.30.0 | Apache-2.0 | https://github.com/MagicStack/asyncpg |
| [greenlet](https://github.com/python-greenlet/greenlet) | ≥3.0.0 | MIT | https://github.com/python-greenlet/greenlet |
| [psycopg2-binary](https://github.com/psycopg/psycopg2) | ≥2.9.11 | LGPL-3.0 | https://github.com/psycopg/psycopg2 |

</details>

---

<details>
<summary><strong>Acknowledgments</strong></summary>

MCP Databricks Command Execution API from [databricks-exec-code](https://github.com/databricks-solutions/databricks-exec-code-mcp) by Natyra Bajraktari and Henryk Borzymowski.

</details>
