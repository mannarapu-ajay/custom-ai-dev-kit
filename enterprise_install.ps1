#
# Enterprise AI Dev Kit — Installer (Windows)
#
# Usage:
#   .\enterprise_install.ps1
#   .\enterprise_install.ps1 -Profile DEFAULT -Force
#   .\enterprise_install.ps1 -SkillsOnly
#   .\enterprise_install.ps1 -Global
#
# Environment overrides:
#   $env:DEVKIT_PROFILE = "NAME"
#   $env:DEVKIT_FORCE   = "true"
#

$ErrorActionPreference = "Stop"

# =============================================================================
# -- ENTERPRISE CONFIGURATION  (edit this section for your organisation) ------
# =============================================================================

$EnterpriseName    = "McCain"
$EnterpriseDisplay = "McCain"
$EnterpriseOrg     = "McCainFoods"   # GitHub org or user that owns the enterprise skills repo

# Enterprise skills source mode.
#   "git"   - clone/pull from a private remote repo (derived from EnterpriseOrg + EnterpriseName)
#   "local" - use a path on disk (set EnterpriseSkillsPath below; defaults to .\enterprise_skills\)
$EnterpriseSkillsMode = "git"

# Used when EnterpriseSkillsMode = "git"
# Repo URL - defaults to <EnterpriseOrg>/<EnterpriseName>-skills if left as-is.
# Override with any SSH clone URL if your skills live in a different repo.
$EnterpriseSkillsRepo = "git@github.com:${EnterpriseOrg}/DAIA-data-architecture-skills.git"
# Subfolder inside the repo where skill directories live.
# Leave empty if skills are at the root of the repo.
# Example: "skills/enterprise"  or  "claude-skills"
$EnterpriseSkillsRepoSubpath = "mccain-data-architecture-skills"

# Used when EnterpriseSkillsMode = "local"
# Leave empty to use the enterprise_skills\ folder inside this repo.
# Or set an absolute path to any directory that contains skill sub-folders.
$EnterpriseSkillsPath = ""

# GitHub Enterprise - set if your org uses GitHub Enterprise Server (not github.com).
# Example: "https://github.mccainfoods.com/api/v3"
# Leave empty to use public github.com.
$GitHubApiUrl = ""

# Databricks workspace catalog - add or remove entries as domains change.
$WorkspaceNames = @(
    "Growth", "Supply Chain", "Finance", "Agriculture",
    "HR", "Procurement", "EDP", "Enter URL manually"
)
$WorkspaceUrls = @(
    "https://adb-982288893326755.15.azuredatabricks.net",
    "https://adb-1534255211069001.1.azuredatabricks.net",
    "https://adb-3107134495216511.11.azuredatabricks.net",
    "https://adb-54001242538101.1.azuredatabricks.net",
    "https://adb-2199059861738382.2.azuredatabricks.net",
    "https://adb-360325603937068.8.azuredatabricks.net",
    "https://adb-849096460664268.8.azuredatabricks.net",
    ""
)

# =============================================================================
# -- PATHS  (derived - do not edit) -------------------------------------------
# =============================================================================

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir  = if ($env:AIDEVKIT_HOME) { $env:AIDEVKIT_HOME } else { Join-Path $env:USERPROFILE ".ai-dev-kit" }
$VenvDir     = Join-Path $InstallDir ".venv"
$VenvPython  = Join-Path $VenvDir "Scripts\python.exe"
$McpEntry    = Join-Path $ScriptDir "databricks-mcp-server\run_server.py"

$EntSkillsLocal   = Join-Path $ScriptDir "enterprise_skills"
$EntSkillsRepoDir = Join-Path $InstallDir "$EnterpriseName-skills-repo"
$UpdateCheckCmd   = "powershell -File `"$(Join-Path $ScriptDir '.claude-plugin\check_update.ps1')`""
$StateSubdir      = ".$EnterpriseName-adk"

# Early sanity check - confirm this is the correct repo directory
if (-not (Test-Path (Join-Path $ScriptDir "databricks-mcp-server")) -or
    -not (Test-Path (Join-Path $ScriptDir "databricks-tools-core"))) {
    Write-Host ""
    Write-Host "  x Could not locate the custom-ai-dev-kit repo at: $ScriptDir" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Do NOT copy this script - run it directly using its full path from any directory:"
    Write-Host ""
    Write-Host "    powershell -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1"
    Write-Host ""
    Write-Host "  You can run this from inside your project directory, e.g.:"
    Write-Host "    cd C:\my-project"
    Write-Host "    powershell -File C:\path\to\custom-ai-dev-kit\enterprise_install.ps1"
    Write-Host ""
    exit 1
}

# =============================================================================
# -- DEFAULTS  (overridable by flags / env vars) -------------------------------
# =============================================================================

$script:Profile_        = if ($env:DEVKIT_PROFILE) { $env:DEVKIT_PROFILE } else { "DEFAULT" }
$script:Scope           = if ($env:DEVKIT_SCOPE)   { $env:DEVKIT_SCOPE }   else { "project" }
$script:Force           = $env:DEVKIT_FORCE -eq "true"
$script:InstallMcp      = $true
$script:InstallSkills   = $true
$script:SkillsProfile   = ""
$script:Silent          = $false
$script:ProfileProvided = $false
$script:ProjectDir      = ""
$script:WorkspaceUrl    = ""

# =============================================================================
# -- PARSE FLAGS --------------------------------------------------------------
# =============================================================================

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        { $_ -in "-p","--profile","-Profile" }       { $script:Profile_ = $args[$i+1]; $script:ProfileProvided = $true; $i += 2 }
        { $_ -in "-g","--global","-Global" }          { $script:Scope = "global"; $i++ }
        { $_ -in "--skills-only","-SkillsOnly" }      { $script:InstallMcp = $false; $i++ }
        { $_ -in "--mcp-only","-McpOnly" }            { $script:InstallSkills = $false; $i++ }
        { $_ -in "--skills-profile","-SkillsProfile" }{ $script:SkillsProfile = $args[$i+1]; $i += 2 }
        { $_ -in "--silent","-Silent" }               { $script:Silent = $true; $i++ }
        { $_ -in "-f","--force","-Force" }            { $script:Force = $true; $i++ }
        { $_ -in "-h","--help","-Help" } {
            Write-Host ""
            Write-Host "$EnterpriseDisplay Enterprise AI Dev Kit Installer"
            Write-Host ""
            Write-Host "Usage: .\enterprise_install.ps1 [OPTIONS]"
            Write-Host ""
            Write-Host "Options:"
            Write-Host "  -Profile NAME        Databricks profile (default: DEFAULT)"
            Write-Host "  -Global              Install globally (not per-project)"
            Write-Host "  -SkillsOnly          Skip MCP server setup"
            Write-Host "  -McpOnly             Skip skills installation"
            Write-Host "  -SkillsProfile LIST  Skill profiles: all,data-engineer,analyst,ai-ml-engineer,app-developer"
            Write-Host "  -Silent              No output except errors"
            Write-Host "  -Force               Force reinstall"
            Write-Host ""
            Write-Host "Environment variables:"
            Write-Host "  DEVKIT_PROFILE       Databricks config profile"
            Write-Host "  DEVKIT_FORCE         Set to 'true' to force reinstall"
            Write-Host "  AIDEVKIT_HOME        MCP install dir (default: ~\.ai-dev-kit)"
            Write-Host ""
            exit 0
        }
        default { Write-Error "Unknown option: $($args[$i]) (use -Help for help)"; exit 1 }
    }
}

# =============================================================================
# -- OUTPUT HELPERS -----------------------------------------------------------
# =============================================================================

# Refresh PATH from registry, then probe known winget install dirs for a binary.
# Returns $true if the command is now resolvable, $false otherwise.
function Add-WingetInstalledPath {
    param([string]$ExeName)
    # 1. Refresh PATH from registry
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
    if (Get-Command $ExeName -ErrorAction SilentlyContinue) { return $true }
    # 2. Test-Path against exact dirs winget uses — no recursion, no exit codes
    $knownDirs = @(
        "$env:ProgramFiles\nodejs",
        "$env:ProgramFiles\GitHub CLI",
        "$env:ProgramW6432\nodejs",
        "$env:LOCALAPPDATA\Programs\nodejs",
        "$env:LOCALAPPDATA\Programs\GitHub CLI"
    )
    foreach ($dir in $knownDirs) {
        if (Test-Path (Join-Path $dir $ExeName) -ErrorAction SilentlyContinue) {
            $env:Path = "$dir;" + $env:Path
            return $true
        }
    }
    return $false
}

function Write-Msg  { param($m) if (-not $script:Silent) { Write-Host "  $m" } }
function Write-Ok   { param($m) if (-not $script:Silent) { Write-Host "  " -NoNewline; Write-Host "v " -ForegroundColor Green -NoNewline; Write-Host $m } }
function Write-Warn { param($m) if (-not $script:Silent) { Write-Host "  " -NoNewline; Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $m } }
function Write-Die  { param($m) Write-Host "  " -NoNewline; Write-Host "x $m" -ForegroundColor Red; exit 1 }
function Write-Step {
    param($m)
    if (-not $script:Silent) {
        Write-Host ""
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host "  $m" -ForegroundColor White
        Write-Host "--------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
    }
}

# =============================================================================
# -- INTERACTIVE HELPERS ------------------------------------------------------
# =============================================================================

function Read-Prompt {
    param([string]$PromptText, [string]$Default = "")
    if ($script:Silent) { return $Default }
    $response = Read-Host "  $PromptText [$Default]"
    if ([string]::IsNullOrWhiteSpace($response)) { return $Default }
    return $response
}

function Invoke-RadioSelect {
    param([string]$Title, [string[]]$Items)

    if ($script:Silent) {
        $first = $Items[0] -split '\|'
        return $first[1]
    }

    # Parse items: "Label|Value|Hint"
    $labels = @(); $values = @(); $hints = @()
    foreach ($item in $Items) {
        $parts = $item -split '\|', 3
        $labels += $parts[0]
        $values += $parts[1]
        $hints  += if ($parts.Count -gt 2) { $parts[2] } else { "" }
    }
    $count      = $labels.Count
    $cursor     = 0
    $selected   = 0
    $labelWidth = ($labels | Measure-Object -Property Length -Maximum).Maximum

    # Non-interactive fallback (no console / output redirected)
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
        Write-Host "  $Title"
        for ($j = 0; $j -lt $count; $j++) {
            Write-Host "    $($j+1)) $($labels[$j])  $($hints[$j])"
        }
        $raw = Read-Host "  Enter number [1]"
        $idx = if ($raw -match '^\d+$') { [int]$raw - 1 } else { 0 }
        if ($idx -lt 0 -or $idx -ge $count) { $idx = 0 }
        return $values[$idx]
    }

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    Write-Host "  (up/down arrows to navigate, Enter to confirm)" -ForegroundColor DarkGray
    Write-Host ""

    # Reserve lines first, then calculate startRow from current cursor position.
    # This handles console scroll: if writing blank lines scrolls the buffer,
    # $startRow computed before would point off-screen and cause SetCursorPosition errors.
    $listHeight = $count + 2
    for ($r = 0; $r -lt $listHeight; $r++) { Write-Host "" }
    $startRow = [Math]::Max(0, [Console]::CursorTop - $listHeight)

    # Redraw using absolute cursor positioning - no relative movement artifacts
    $redraw = {
        $winW = [Console]::WindowWidth
        for ($idx = 0; $idx -lt $count; $idx++) {
            [Console]::SetCursorPosition(0, $startRow + $idx)
            $arrow = "    "
            $dot   = "o"
            $color = [ConsoleColor]::DarkGray
            if ($idx -eq $cursor)   { $arrow = "  > " }
            if ($idx -eq $selected) { $dot = "*"; $color = [ConsoleColor]::Green }
            $line = "  $arrow$dot  $($labels[$idx].PadRight($labelWidth))   $($hints[$idx])"
            $line = $line.PadRight($winW - 1).Substring(0, [Math]::Min($line.Length + ($winW - 1 - $line.Length), $winW - 1))
            $prev = [Console]::ForegroundColor
            [Console]::ForegroundColor = $color
            [Console]::Write($line.PadRight($winW - 1))
            [Console]::ForegroundColor = $prev
        }
        # Blank separator line
        [Console]::SetCursorPosition(0, $startRow + $count)
        [Console]::Write("".PadRight([Console]::WindowWidth - 1))
        # Confirm button
        [Console]::SetCursorPosition(0, $startRow + $count + 1)
        $confirmLine = if ($cursor -eq $count) { "  > [ Confirm ]" } else { "    [ Confirm ]" }
        $confirmColor = if ($cursor -eq $count) { [ConsoleColor]::Cyan } else { [ConsoleColor]::DarkGray }
        $prev = [Console]::ForegroundColor
        [Console]::ForegroundColor = $confirmColor
        [Console]::Write($confirmLine.PadRight([Console]::WindowWidth - 1))
        [Console]::ForegroundColor = $prev
    }

    [Console]::CursorVisible = $false
    try {
        & $redraw
        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($cursor -gt 0)      { $cursor-- } }
                "DownArrow" { if ($cursor -lt $count)  { $cursor++ } }
                "Spacebar"  { if ($cursor -lt $count)  { $selected = $cursor } }
                "Enter" {
                    if ($cursor -lt $count) { $selected = $cursor }
                    & $redraw
                    # Move cursor below the list before returning
                    [Console]::SetCursorPosition(0, $startRow + $count + 2)
                    [Console]::CursorVisible = $true
                    return $values[$selected]
                }
            }
            & $redraw
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# =============================================================================
# -- BANNER -------------------------------------------------------------------
# =============================================================================

Write-Host ""
$_bw = 56
$_bt = "   $EnterpriseDisplay — Enterprise AI Dev Kit Installer"
Write-Host ("╔" + ("═" * $_bw) + "╗") -ForegroundColor Cyan
Write-Host ("║" + $_bt.PadRight($_bw) + "║") -ForegroundColor Cyan
Write-Host ("╚" + ("═" * $_bw) + "╝") -ForegroundColor Cyan
Write-Host ""
Write-Warn "NOTE: Do NOT run the official Databricks install.ps1 alongside this script."
Write-Msg  "  This enterprise installer fully replaces it. Running both will break the MCP config."
Write-Host ""

# =============================================================================
# -- STEP 1: PROJECT DIRECTORY ------------------------------------------------
# =============================================================================

Write-Step "Step 1 of 9 — Project Directory"

$script:ProjectDir = Read-Prompt "Project directory" (Get-Location).Path
if (-not (Test-Path $script:ProjectDir)) { New-Item -ItemType Directory -Path $script:ProjectDir -Force | Out-Null }
$script:ProjectDir = (Resolve-Path $script:ProjectDir).Path
Write-Ok "Project dir: $($script:ProjectDir)"

$StateDirPath = Join-Path $script:ProjectDir $StateSubdir
if ($script:Scope -eq "global") { $StateDirPath = Join-Path $InstallDir $StateSubdir }

foreach ($d in @(
    (Join-Path $script:ProjectDir ".claude\skills"),
    $StateDirPath,
    (Join-Path $script:ProjectDir "src\generated"),
    (Join-Path $script:ProjectDir "instruction-templates")
)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue | Out-Null }

Write-Ok "Workspace directories created"

# =============================================================================
# -- STEP 2: PREREQUISITES ----------------------------------------------------
# =============================================================================

Write-Step "Step 2 of 9 — Prerequisites"

# git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Die "git required. Install: https://git-scm.com" }
$gitVer = & git --version 2>&1
Write-Ok "git $gitVer"

# npx / Node.js (needed for GitHub MCP + Atlassian MCP)
if (Get-Command npx -ErrorAction SilentlyContinue) {
    $nodeVer = & node --version 2>$null
    Write-Ok "Node.js $nodeVer / npx"
} else {
    Write-Warn "Node.js not found — installing via winget..."
    try {
        & winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (Add-WingetInstalledPath "npx.cmd") {
            Write-Ok "Node.js $(& node --version 2>$null) / npx (just installed)"
        } else {
            Write-Warn "Node.js installed but npx not in PATH — restart your terminal or install manually: https://nodejs.org"
        }
    } catch {
        Write-Warn "Could not auto-install Node.js — install manually: https://nodejs.org"
    }
}

# gh CLI (needed for GitHub MCP OAuth)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghVer = & gh --version 2>&1 | Select-Object -First 1
    Write-Ok "gh CLI: $ghVer"
} else {
    Write-Warn "gh CLI not found — installing via winget..."
    try {
        & winget install GitHub.cli --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (Add-WingetInstalledPath "gh.exe") {
            Write-Ok "gh CLI: $(& gh --version 2>&1 | Select-Object -First 1) (just installed)"
        } else {
            Write-Warn "gh CLI installed but not in PATH — restart your terminal or install manually: https://cli.github.com"
        }
    } catch {
        Write-Warn "Could not auto-install gh CLI — install manually: https://cli.github.com"
    }
}

# SSH access to GitHub (needed only when pulling enterprise skills from a remote git repo)
if ($EnterpriseSkillsMode -eq "git" -and $EnterpriseSkillsRepo) {
    try { $sshOut = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) | Out-String } catch { $sshOut = "" }
    if ($sshOut -match "Hi ") {
        Write-Ok "SSH access to github.com"
    } else {
        Write-Warn "SSH access to github.com not verified — private skills repo clone may fail"
        Write-Msg  "  Configure SSH: ssh-keygen -t ed25519 and add public key to GitHub"
    }
}

# uv (Python package manager for MCP server)
if (Get-Command uv -ErrorAction SilentlyContinue) {
    Write-Ok "$(& uv --version)"
} else {
    Write-Warn "uv not found — installing..."
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Write-Die "uv install failed. Run: Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression" }
    Write-Ok "$(& uv --version) (just installed)"
}

# Databricks CLI
if (Get-Command databricks -ErrorAction SilentlyContinue) {
    Write-Ok "Databricks CLI: $(& databricks --version 2>&1 | Select-Object -First 1)"
} else {
    Write-Warn "Databricks CLI not found — installing via winget..."
    try {
        & winget install Databricks.DatabricksCLI --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command databricks -ErrorAction SilentlyContinue) {
            Write-Ok "Databricks CLI: $(& databricks --version 2>&1 | Select-Object -First 1) (just installed)"
        } else {
            Write-Warn "Databricks CLI installed but not in PATH yet — restart your terminal after this script."
        }
    } catch {
        Write-Warn "Could not auto-install Databricks CLI."
        Write-Msg  "  Run manually: winget install Databricks.DatabricksCLI"
    }
}

# =============================================================================
# -- STEP 3: DATABRICKS WORKSPACE & PROFILE -----------------------------------
# =============================================================================

Write-Step "Step 3 of 9 — Databricks Workspace & Profile"

# -- Workspace selection ------------------------------------------------------
$wsItems = @()
for ($wi = 0; $wi -lt $WorkspaceNames.Count; $wi++) {
    $url  = $WorkspaceUrls[$wi]
    $hint = if ($url) { $url } else { "enter URL manually" }
    $wsItems += "$($WorkspaceNames[$wi])|$($WorkspaceNames[$wi])|$hint"
}
$wsName = Invoke-RadioSelect "Choose your Databricks domain / workspace:" $wsItems

$script:WorkspaceUrl = ""
for ($wi = 0; $wi -lt $WorkspaceNames.Count; $wi++) {
    if ($WorkspaceNames[$wi] -eq $wsName) { $script:WorkspaceUrl = $WorkspaceUrls[$wi]; break }
}
if (-not $script:WorkspaceUrl) {
    $script:WorkspaceUrl = Read-Prompt "Databricks workspace URL" "https://"
} else {
    Write-Ok "Workspace: $wsName  ->  $($script:WorkspaceUrl)"
}
$script:WorkspaceUrl = $script:WorkspaceUrl.TrimEnd('/')

# -- Profile selection --------------------------------------------------------
if (-not $script:ProfileProvided -and -not $script:Silent) {
    $dbCfg = Join-Path $env:USERPROFILE ".databrickscfg"
    $knownProfiles = @()
    if (Test-Path $dbCfg) {
        Get-Content $dbCfg | ForEach-Object {
            if ($_ -match '^\[([a-zA-Z0-9_-]+)\]$') { $knownProfiles += $Matches[1] }
        }
    }
    Write-Host ""
    if ($knownProfiles.Count -gt 0) {
        $pitems = @()
        foreach ($p in $knownProfiles) {
            $hint = if ($p -eq "DEFAULT") { "default" } else { "" }
            $pitems += "$p|$p|$hint"
        }
        $pitems += "Custom profile name...|__CUSTOM__|enter a name"
        $script:Profile_ = Invoke-RadioSelect "Choose Databricks profile:" $pitems
        if ($script:Profile_ -eq "__CUSTOM__") {
            $script:Profile_ = Read-Prompt "Profile name" "DEFAULT"
        } else {
            Write-Ok "Profile: $($script:Profile_)"
        }
    } else {
        Write-Msg "No .databrickscfg found — you can authenticate after install."
        $script:Profile_ = Read-Prompt "Profile name" "DEFAULT"
    }
}

# -- OAuth login if not already authenticated ---------------------------------
Write-Host ""
if (Get-Command databricks -ErrorAction SilentlyContinue) {
    try {
        $authJson = & databricks current-user me --profile $script:Profile_ --output json 2>$null
        $authUser = if ($authJson) { ($authJson | ConvertFrom-Json).userName } else { "" }
    } catch { $authUser = "" }
    if ($authUser) {
        Write-Ok "Already authenticated as $authUser"
    } else {
        Write-Warn "Not authenticated — opening browser for OAuth login..."
        & databricks auth login --host $script:WorkspaceUrl --profile $script:Profile_
    }
}

# =============================================================================
# -- STEP 4: AUTHENTICATION + CA CERTIFICATES ---------------------------------
# =============================================================================

Write-Step "Step 4 of 9 — Authentication + CA Certificates"

if (Get-Command databricks -ErrorAction SilentlyContinue) {
    try {
        $authJson = & databricks current-user me --profile $script:Profile_ --output json 2>$null
        $authUser = if ($authJson) { ($authJson | ConvertFrom-Json).userName } else { "" }
    } catch { $authUser = "" }
    if ($authUser) {
        Write-Ok "Authenticated as $authUser"
    } else {
        Write-Warn "Auth could not be confirmed. Re-authenticate later:"
        Write-Msg  "  databricks auth login --host $($script:WorkspaceUrl) --profile $($script:Profile_)"
    }
}

# -- Corporate CA certificates ------------------------------------------------
$caBundle = Join-Path $env:USERPROFILE ".$EnterpriseName-adk\ca-bundle.pem"

if ($env:NODE_EXTRA_CA_CERTS -and (Test-Path $env:NODE_EXTRA_CA_CERTS)) {
    # already configured - also configure npm
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        & npm config set cafile $env:NODE_EXTRA_CA_CERTS 2>$null | Out-Null
    }
} else {
    Write-Host ""
    Write-Msg "Configuring corporate CA certificates..."
    New-Item -ItemType Directory -Path (Split-Path $caBundle) -Force -ErrorAction SilentlyContinue | Out-Null
    try {
        # Export from Windows certificate store
        $certs = Get-ChildItem -Path Cert:\LocalMachine\Root
        $pemLines = @()
        foreach ($cert in $certs) {
            $pemLines += "-----BEGIN CERTIFICATE-----"
            $pemLines += [Convert]::ToBase64String($cert.RawData, 'InsertLineBreaks')
            $pemLines += "-----END CERTIFICATE-----"
        }
        $pemLines | Set-Content $caBundle -Encoding UTF8
        $env:NODE_EXTRA_CA_CERTS = $caBundle
        # Persist to user environment
        [System.Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $caBundle, "User")
        # Configure npm to use the same CA bundle (fixes npx/mcp-remote SSL errors)
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            & npm config set cafile $caBundle 2>$null | Out-Null
        }
        Write-Ok "CA bundle written -> $caBundle"
    } catch {
        Write-Warn "Could not extract CA certs — set manually:"
        Write-Msg  "  `$env:NODE_EXTRA_CA_CERTS = 'C:\path\to\bundle.crt'"
    }
}

# =============================================================================
# -- STEP 5: DATABRICKS MCP ---------------------------------------------------
# =============================================================================

Write-Step "Step 5 of 9 — Databricks MCP"

$McpConfig = Join-Path $script:ProjectDir ".mcp.json"

if ($script:InstallMcp) {
    Write-Msg "Setting up Databricks MCP server..."
    if (-not (Test-Path (Join-Path $ScriptDir "databricks-mcp-server"))) { Write-Die "databricks-mcp-server not found in $ScriptDir" }

    # Always reinstall from this repo - ensures venv uses custom-ai-dev-kit packages,
    # not stale ones from a previous official install run.
    New-Item -ItemType Directory -Path $VenvDir -Force -ErrorAction SilentlyContinue | Out-Null
    & uv venv --python 3.11 --allow-existing $VenvDir -q 2>$null
    if ($LASTEXITCODE -ne 0) { & uv venv --allow-existing $VenvDir -q }
    Write-Msg "Installing Python dependencies..."
    # --native-tls: use system certificate store (required behind corporate TLS-intercepting proxies)
    & uv pip install --python $VenvPython --native-tls `
        -e (Join-Path $ScriptDir "databricks-tools-core") `
        -e (Join-Path $ScriptDir "databricks-mcp-server") --quiet
    & $VenvPython -c "import databricks_mcp_server" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Die "MCP server import failed after install." }
    Write-Ok "MCP server ready  ->  $VenvDir"
}

# -- Write .mcp.json with Databricks entry ------------------------------------
$mcpJson = if (Test-Path $McpConfig) {
    try { Get-Content $McpConfig -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{} }
} else { [PSCustomObject]@{} }

if (-not $mcpJson.PSObject.Properties['mcpServers']) {
    $mcpJson | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{})
}

$dbEnv = [PSCustomObject]@{ DATABRICKS_CONFIG_PROFILE = $script:Profile_ }
if ($env:NODE_EXTRA_CA_CERTS) {
    $dbEnv | Add-Member -NotePropertyName 'NODE_EXTRA_CA_CERTS' -NotePropertyValue $env:NODE_EXTRA_CA_CERTS
}

$mcpJson.mcpServers | Add-Member -NotePropertyName 'databricks' -NotePropertyValue ([PSCustomObject]@{
    command       = $VenvPython
    args          = @($McpEntry)
    defer_loading = $true
    env           = $dbEnv
}) -Force

$mcpJson | ConvertTo-Json -Depth 10 | Set-Content $McpConfig -Encoding UTF8
Write-Ok "Databricks MCP  ->  $McpConfig"

# =============================================================================
# -- STEP 6: GITHUB MCP -------------------------------------------------------
# =============================================================================

Write-Step "Step 6 of 9 — GitHub MCP"

# -- Add GitHub entry to .mcp.json --------------------------------------------
$mcpJson = Get-Content $McpConfig -Raw | ConvertFrom-Json
$githubEnv = [PSCustomObject]@{ GITHUB_PERSONAL_ACCESS_TOKEN = "" }
if ($GitHubApiUrl) { $githubEnv | Add-Member -NotePropertyName 'GITHUB_API_URL' -NotePropertyValue $GitHubApiUrl }
if ($env:NODE_EXTRA_CA_CERTS) { $githubEnv | Add-Member -NotePropertyName 'NODE_EXTRA_CA_CERTS' -NotePropertyValue $env:NODE_EXTRA_CA_CERTS }
$mcpJson.mcpServers | Add-Member -NotePropertyName 'github' -NotePropertyValue ([PSCustomObject]@{
    command = "npx"
    args    = @("-y", "@modelcontextprotocol/server-github")
    env     = $githubEnv
}) -Force
$mcpJson | ConvertTo-Json -Depth 10 | Set-Content $McpConfig -Encoding UTF8

# -- OAuth via gh CLI ---------------------------------------------------------
Write-Msg "Authenticating GitHub MCP via OAuth..."
if (Get-Command gh -ErrorAction SilentlyContinue) {
    try { $ghUser = & gh api user --jq '.login' 2>$null } catch { $ghUser = "" }
    if ($ghUser) {
        Write-Ok "GitHub: already authenticated as $ghUser"
    } else {
        Write-Msg "Opening browser for GitHub OAuth login..."
        # Run login; ignore non-zero exit from "key already in use" - auth may still succeed
        try { & gh auth login --web --git-protocol ssh 2>&1 | Out-Null } catch {}
        try { $ghUser = & gh api user --jq '.login' 2>$null } catch { $ghUser = "" }
        if (-not $ghUser) {
            Write-Warn "GitHub auth could not be confirmed — token may still work"
        }
    }
    try { $ghToken = & gh auth token 2>$null } catch { $ghToken = "" }
    if ($ghToken) {
        $mcpJson = Get-Content $McpConfig -Raw | ConvertFrom-Json
        $mcpJson.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN = $ghToken
        $mcpJson | ConvertTo-Json -Depth 10 | Set-Content $McpConfig -Encoding UTF8
        Write-Ok "GitHub MCP authenticated as $(if ($ghUser) { $ghUser } else { 'unknown' })"
    } else {
        Write-Warn "Could not retrieve GitHub token — edit GITHUB_PERSONAL_ACCESS_TOKEN in .mcp.json manually"
    }
} else {
    Write-Warn "gh CLI not found — install it for OAuth: https://cli.github.com"
    Write-Warn "Or set GITHUB_PERSONAL_ACCESS_TOKEN manually in .mcp.json"
}

# =============================================================================
# -- STEP 7: ATLASSIAN MCP ----------------------------------------------------
# =============================================================================

Write-Step "Step 7 of 9 — Atlassian MCP"

# -- Add Atlassian entry to .mcp.json -----------------------------------------
$mcpJson = Get-Content $McpConfig -Raw | ConvertFrom-Json
$atlassianEntry = [PSCustomObject]@{
    command = "npx"
    args    = @("mcp-remote", "https://mcp.atlassian.com/v1/mcp", "--transport", "http-first")
}
if ($env:NODE_EXTRA_CA_CERTS) {
    $atlassianEntry | Add-Member -NotePropertyName 'env' -NotePropertyValue ([PSCustomObject]@{
        NODE_EXTRA_CA_CERTS = $env:NODE_EXTRA_CA_CERTS
    })
}
$mcpJson.mcpServers | Add-Member -NotePropertyName 'atlassian' -NotePropertyValue $atlassianEntry -Force
$mcpJson | ConvertTo-Json -Depth 10 | Set-Content $McpConfig -Encoding UTF8
Write-Ok "Atlassian MCP entry added  ->  $McpConfig"

# -- OAuth via mcp-remote (browser) -------------------------------------------
Write-Msg "Authenticating Atlassian MCP (Confluence + Jira) via OAuth..."
if (Get-Command npx -ErrorAction SilentlyContinue) {
    $doAtlassian = Read-Prompt "Authenticate with Atlassian now? (y/n)" "y"
    if ($doAtlassian -in @("y", "Y")) {
        Write-Msg "Starting OAuth flow — a browser window will open."
        Write-Msg "Sign in with your Atlassian account, then press Enter here to continue."
        Write-Host ""
        $atlProc = Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c", "npx mcp-remote https://mcp.atlassian.com/v1/mcp --transport http-first" `
            -PassThru -WindowStyle Minimized
        Start-Sleep -Seconds 4
        Read-Prompt "Press Enter after completing Atlassian authentication in the browser" ""
        if ($atlProc -and -not $atlProc.HasExited) {
            try { & taskkill /F /T /PID $atlProc.Id 2>&1 | Out-Null } catch {}
        }
        Write-Ok "Atlassian MCP authenticated"
    } else {
        Write-Msg "Skipped — OAuth will prompt automatically on first MCP use."
        Write-Ok "Atlassian MCP configured"
    }
} else {
    Write-Warn "npx not found — Atlassian MCP OAuth skipped. Install Node.js first."
}

# =============================================================================
# -- STEP 8: SKILLS + SETTINGS ------------------------------------------------
# =============================================================================

Write-Step "Step 8 of 9 — Skills + Settings"

# -- Write .claude/settings.json ----------------------------------------------
$settingsPath = Join-Path $script:ProjectDir ".claude\settings.json"
New-Item -ItemType Directory -Path (Split-Path $settingsPath) -Force -ErrorAction SilentlyContinue | Out-Null
$settingsJson = if (Test-Path $settingsPath) {
    try { Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{} }
} else { [PSCustomObject]@{} }

if (-not $settingsJson.PSObject.Properties['hooks']) {
    $settingsJson | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}
if (-not $settingsJson.hooks.PSObject.Properties['SessionStart']) {
    $settingsJson.hooks | Add-Member -NotePropertyName 'SessionStart' -NotePropertyValue @()
}
$hasUpdateHook = $settingsJson.hooks.SessionStart | Where-Object {
    ($_.hooks | Where-Object { $_.command -match "check_update" }) -ne $null
}
if (-not $hasUpdateHook) {
    $settingsJson.hooks.SessionStart += [PSCustomObject]@{
        hooks = @([PSCustomObject]@{ type = "command"; command = $UpdateCheckCmd; timeout = 5 })
    }
}
$settingsJson | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Ok ".claude/settings.json  ->  $settingsPath"

# -- Install skills -----------------------------------------------------------
$dbCount  = 0
$entCount = 0
if ($script:InstallSkills) {
    Write-Host ""
    Write-Msg "Installing skills..."
    $skillsDest = Join-Path $script:ProjectDir ".claude\skills"
    New-Item -ItemType Directory -Path $skillsDest -Force -ErrorAction SilentlyContinue | Out-Null

    # Databricks skills - from this repo
    $dbSkillsDir = Join-Path $ScriptDir "databricks-skills"
    if (Test-Path $dbSkillsDir) {
        Get-ChildItem -Path $dbSkillsDir -Directory | Where-Object { $_.Name -ne "TEMPLATE" } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $skillsDest $_.Name) -Recurse -Force
            $dbCount++
        }
    }
    Write-Ok "Databricks skills  ($dbCount installed)"

    # Enterprise skills - git repo or local path, controlled by EnterpriseSkillsMode
    $entSource = ""

    if ($EnterpriseSkillsMode -eq "git") {
        if (-not $EnterpriseSkillsRepo) {
            Write-Warn "EnterpriseSkillsMode=git but EnterpriseSkillsRepo is empty — skipping"
        } elseif (Test-Path (Join-Path $EntSkillsRepoDir ".git")) {
            $currentRemote = & git -C $EntSkillsRepoDir remote get-url origin 2>$null
            if ($currentRemote -ne $EnterpriseSkillsRepo) {
                Write-Msg "Enterprise skills repo URL changed — re-cloning..."
                Remove-Item -Path $EntSkillsRepoDir -Recurse -Force
                try { & git clone -q --depth 1 $EnterpriseSkillsRepo $EntSkillsRepoDir 2>&1 | Out-Null } catch {}
                if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Write-Warn "Failed to re-clone enterprise skills repo" }
            } else {
                try { & git -C $EntSkillsRepoDir fetch -q --depth 1 origin main 2>&1 | Out-Null } catch {}
                try { & git -C $EntSkillsRepoDir reset --hard FETCH_HEAD 2>&1 | Out-Null } catch {}
                if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Write-Warn "Failed to update enterprise skills repo" }
            }
        } else {
            New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction SilentlyContinue | Out-Null
            try { & git clone -q --depth 1 $EnterpriseSkillsRepo $EntSkillsRepoDir 2>&1 | Out-Null } catch {}
            if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Write-Warn "Failed to clone enterprise skills repo ($EnterpriseSkillsRepo)" }
        }
    } else {
        $localPath = if ($EnterpriseSkillsPath) { $EnterpriseSkillsPath } else { $EntSkillsLocal }
        if (Test-Path $localPath) { $entSource = $localPath } else { Write-Warn "Local enterprise skills path not found: $localPath" }
    }

    # Apply subfolder path if specified
    if ($entSource -and $EnterpriseSkillsRepoSubpath) {
        $entSource = Join-Path $entSource $EnterpriseSkillsRepoSubpath
        if (-not (Test-Path $entSource)) {
            Write-Warn "Subfolder not found in repo: $EnterpriseSkillsRepoSubpath"
            $entSource = ""
        }
    }

    if ($entSource -and (Test-Path $entSource)) {
        Get-ChildItem -Path $entSource -Directory | Where-Object { $_.Name -ne "TEMPLATE" } | ForEach-Object {
            if (Test-Path (Join-Path $_.FullName "SKILL.md")) {
                Copy-Item -Path $_.FullName -Destination (Join-Path $skillsDest $_.Name) -Recurse -Force
                $entCount++
            }
        }
        Write-Ok "Enterprise skills  ($entCount installed)  <- $entSource"
    } else {
        Write-Warn "No enterprise skills source found — skipping"
    }
}

# =============================================================================
# -- STEP 9: WORKSPACE + VERSION LOCK -----------------------------------------
# =============================================================================

Write-Step "Step 9 of 9 — Workspace + Version Lock"

# -- .gitignore ---------------------------------------------------------------
$gitignore = Join-Path $script:ProjectDir ".gitignore"
if (-not (Test-Path $gitignore)) { New-Item -ItemType File -Path $gitignore -Force | Out-Null }
$giContent = Get-Content $gitignore -ErrorAction SilentlyContinue
foreach ($rule in @("$StateSubdir/", ".claude/", ".mcp.json", "src/generated/", ".databricks/", ".env", "__pycache__/", "*.pyc")) {
    if ($giContent -notcontains $rule) { Add-Content $gitignore $rule }
}
Write-Ok ".gitignore updated"

# -- src/generated/README.md --------------------------------------------------
$genReadme = Join-Path $script:ProjectDir "src\generated\README.md"
if (-not (Test-Path $genReadme)) {
    @"
# Generated Code

This directory is managed by Claude Code.
All AI-generated code is placed here automatically.

> Do not manually edit files in this directory.
"@ | Set-Content $genReadme -Encoding UTF8
}
Write-Ok "src/generated/README.md"

# -- instruction-templates/default.md -----------------------------------------
$tmpl = Join-Path $script:ProjectDir "instruction-templates\default.md"
if (-not (Test-Path $tmpl)) {
    @"
# Project Instructions

This project uses Databricks on the Lakehouse platform.
Enterprise: **$EnterpriseDisplay**
Workspace:  $($script:WorkspaceUrl)

## Code Generation Rules
- ALL generated code MUST go into ``src/generated/``
- Never write generated files outside ``src/generated/``

## Active Skills
- **Databricks skills**: all skills from ai-dev-kit
- **enterprise-naming-convention**: naming standards for all assets
- **enterprise-dynamic-modeling**: config-driven transformation patterns
- **enterprise-data-governance**: PII tagging and data retention policies
- **enterprise-cost-optimization**: cluster policies and cost attribution

## Context
- Catalog: ``<set your catalog>``
- Environment: ``dev | staging | prod``
- Team: ``<set your team>``
"@ | Set-Content $tmpl -Encoding UTF8
}
Write-Ok "instruction-templates/default.md"

# -- metadata.json + version.lock ---------------------------------------------
$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
New-Item -ItemType Directory -Path $StateDirPath -Force -ErrorAction SilentlyContinue | Out-Null

$metaFile = Join-Path $StateDirPath "metadata.json"
$meta = [ordered]@{
    enterprise    = $EnterpriseName
    workspace_url = $script:WorkspaceUrl
    profile       = $script:Profile_
    project_root  = $script:ProjectDir
    created_at    = $now
}
if (Test-Path $metaFile) {
    try {
        $old = Get-Content $metaFile -Raw | ConvertFrom-Json
        foreach ($key in $meta.Keys | Where-Object { $_ -ne "created_at" }) {
            $old | Add-Member -NotePropertyName $key -NotePropertyValue $meta[$key] -Force
        }
        $old | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
    } catch {
        $meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
    }
} else {
    $meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
}

$lock = [ordered]@{
    enterprise_adk       = "enterprise-install"
    enterprise_skills    = "bundled"
    databricks_workspace = $script:WorkspaceUrl
    installed_at         = $now
}
$lock | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $StateDirPath "version.lock") -Encoding UTF8

Write-Ok "$StateSubdir/metadata.json"
Write-Ok "$StateSubdir/version.lock"

# =============================================================================
# -- SUMMARY ------------------------------------------------------------------
# =============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║   v  Workspace Ready                                   ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host ("  {0,-20} {1}" -f "Project",           $script:ProjectDir)
Write-Host ("  {0,-20} {1}" -f "Enterprise",        $EnterpriseDisplay)
Write-Host ("  {0,-20} {1}" -f "Workspace",         $script:WorkspaceUrl)
Write-Host ("  {0,-20} {1}" -f "Profile",           $script:Profile_)
Write-Host ("  {0,-20} {1}" -f "Databricks skills", "$dbCount installed")
Write-Host ("  {0,-20} {1}" -f "Enterprise skills", "$entCount installed")
Write-Host ("  {0,-20} {1}" -f "MCP config",        $McpConfig)
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Open your project in Claude Code:  claude $($script:ProjectDir)" -ForegroundColor Cyan
Write-Host "  2. MCP + skills are active — try: `"List my SQL warehouses`""
Write-Host ""
