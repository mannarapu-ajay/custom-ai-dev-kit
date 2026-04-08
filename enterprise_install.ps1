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
$script:SkillsOnly      = $false
$script:SkillsProfile   = ""
$script:Silent          = $false
$script:ProfileProvided = $false
$script:ProjectDir      = ""
$script:WorkspaceUrl    = ""
$script:SkillsAuthMode  = "ssh"   # overridden in Step 2 if SSH is not set up
$script:HttpsSkillsRepo = $EnterpriseSkillsRepo -replace '^git@github\.com:', 'https://github.com/'

# =============================================================================
# -- PARSE FLAGS --------------------------------------------------------------
# =============================================================================

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        { $_ -in "-p","--profile","-Profile" }       { if (($i+1) -ge $args.Count) { Write-Error "-Profile requires a value"; exit 1 }; $script:Profile_ = $args[$i+1]; $script:ProfileProvided = $true; $i += 2 }
        { $_ -in "-g","--global","-Global" }          { $script:Scope = "global"; $i++ }
        { $_ -in "--skills-only","-SkillsOnly" }      { $script:InstallMcp = $false; $script:SkillsOnly = $true; $i++ }
        { $_ -in "--mcp-only","-McpOnly" }            { $script:InstallSkills = $false; $i++ }
        { $_ -in "--skills-profile","-SkillsProfile" }{ if (($i+1) -ge $args.Count) { Write-Error "--skills-profile requires a value"; exit 1 }; $script:SkillsProfile = $args[$i+1]; $i += 2 }
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
            Write-Host "  -SkillsOnly          Fast path: only update skills (skip Steps 3-7, 9)"
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

function Write-Msg  { param($m) if (-not $script:Silent) { Write-Host "  $m" } }
function Write-Ok   { param($m) if (-not $script:Silent) { Write-Host "  " -NoNewline; Write-Host "✓ " -ForegroundColor Green -NoNewline; Write-Host $m } }
function Write-Warn { param($m) if (-not $script:Silent) { Write-Host "  " -NoNewline; Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $m } }
function Write-Die  { param($m) Write-Host "  " -NoNewline; Write-Host "x $m" -ForegroundColor Red; exit 1 }

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

function Ensure-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return }
    Write-Msg "Scoop not found — installing..."
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch {}
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Refresh-Path
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Warn "Scoop installation failed. Install manually: https://scoop.sh"
    }
}

function Install-GhFromZip {
    # Extracts gh directly to the user profile — no admin, no installer required.
    # Reliable fallback on corporate machines where proxies break Scoop hashes
    # and winget MSI installers require elevation.
    Write-Msg "Installing gh CLI via direct ZIP extraction (no admin required)..."

    $ghDir  = "$env:USERPROFILE\AppData\Local\Programs\gh"
    $tmpZip = "$env:TEMP\gh_windows_amd64.zip"
    $tmpDir = "$env:TEMP\gh_extract"

    # Resolve latest release download URL via GitHub API
    $downloadUrl = $null
    try {
        $release     = Invoke-RestMethod -Uri "https://api.github.com/repos/cli/cli/releases/latest" -UseBasicParsing
        $asset       = $release.assets | Where-Object { $_.name -like "*windows_amd64.zip" } | Select-Object -First 1
        $downloadUrl = $asset.browser_download_url
        Write-Msg "Latest gh release: $($release.tag_name)"
    } catch {
        # Fallback to a known stable version
        $downloadUrl = "https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_windows_amd64.zip"
        Write-Msg "Could not query GitHub API — using fallback version"
    }

    Write-Msg "Downloading gh..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpZip -UseBasicParsing

    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    if (Test-Path $ghDir)  { Remove-Item $ghDir  -Recurse -Force }

    New-Item -ItemType Directory -Path $ghDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    # The zip contains a versioned subdirectory; find gh.exe and copy its parent contents
    $ghExe = Get-ChildItem -Path $tmpDir -Filter "gh.exe" -Recurse | Select-Object -First 1
    if (-not $ghExe) { Write-Die "gh.exe not found in downloaded archive." }
    Copy-Item -Path (Join-Path $ghExe.DirectoryName "*") -Destination $ghDir -Recurse -Force

    # Persist to user PATH so it survives future sessions
    $userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$ghDir*") {
        [System.Environment]::SetEnvironmentVariable("PATH", "$ghDir;$userPath", "User")
    }
    $env:PATH = "$ghDir;" + $env:PATH

    # Cleanup
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
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
    $count    = $labels.Count
    $cursor   = 0

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

    # Reserve lines FIRST so any buffer scrolling happens before we pin $startRow.
    # Then compute startRow by walking back from the current cursor position.
    for ($r = 0; $r -lt ($count + 2); $r++) { Write-Host "" }
    $startRow = [Math]::Max(0, [Console]::CursorTop - ($count + 2))

    # Redraw using absolute cursor positioning - no relative movement artifacts
    $redraw = {
        $winW = [Console]::WindowWidth
        for ($idx = 0; $idx -lt $count; $idx++) {
            try { [Console]::SetCursorPosition(0, $startRow + $idx) } catch { return }
            $arrow = "    "
            $dot   = "o"
            $color = [ConsoleColor]::DarkGray
            if ($idx -eq $cursor) { $arrow = "  > "; $dot = "*"; $color = [ConsoleColor]::Green }
            $line = "  $arrow$dot  $($labels[$idx])   $($hints[$idx])"
            $line = $line.PadRight($winW - 1).Substring(0, [Math]::Min($line.Length + ($winW - 1 - $line.Length), $winW - 1))
            $prev = [Console]::ForegroundColor
            [Console]::ForegroundColor = $color
            [Console]::Write($line.PadRight($winW - 1))
            [Console]::ForegroundColor = $prev
        }
        # Blank separator line
        try { [Console]::SetCursorPosition(0, $startRow + $count) } catch { return }
        [Console]::Write("".PadRight([Console]::WindowWidth - 1))
        # Confirm button
        try { [Console]::SetCursorPosition(0, $startRow + $count + 1) } catch { return }
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
                "Enter" {
                    & $redraw
                    # Move cursor below the list before returning
                    [Console]::SetCursorPosition(0, $startRow + $count + 2)
                    [Console]::CursorVisible = $true
                    return $values[$cursor]
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
$_bannerInner = 56
$_bannerTitle = "   $EnterpriseDisplay — Enterprise AI Dev Kit Installer"
if ($_bannerTitle.Length -gt $_bannerInner) { $_bannerInner = $_bannerTitle.Length + 2 }
Write-Host ("╔" + ("═" * $_bannerInner) + "╗") -ForegroundColor Cyan
Write-Host ("║" + $_bannerTitle.PadRight($_bannerInner) + "║") -ForegroundColor Cyan
Write-Host ("╚" + ("═" * $_bannerInner) + "╝") -ForegroundColor Cyan
Write-Host ""
Write-Warn "NOTE: Do NOT run the official Databricks install.ps1 alongside this script."
Write-Msg  "  This enterprise installer fully replaces it. Running both will break the MCP config."
Write-Host ""

# =============================================================================
# -- STEP 1: PROJECT DIRECTORY ------------------------------------------------
# =============================================================================

if ($script:SkillsOnly) {
    # In skills-only mode just use the current directory — no prompt needed
    $script:ProjectDir = (Get-Location).Path
    Write-Ok "Project dir: $($script:ProjectDir)"
} else {
    Write-Step "Step 1 of 9 — Project Directory"
    $script:ProjectDir = Read-Prompt "Project directory" (Get-Location).Path
    if (-not (Test-Path $script:ProjectDir)) { New-Item -ItemType Directory -Path $script:ProjectDir -Force | Out-Null }
    $script:ProjectDir = (Resolve-Path $script:ProjectDir).Path
    Write-Ok "Project dir: $($script:ProjectDir)"
}

$StateDirPath = Join-Path $script:ProjectDir $StateSubdir
if ($script:Scope -eq "global") { $StateDirPath = Join-Path $InstallDir $StateSubdir }

foreach ($d in @(
    (Join-Path $script:ProjectDir ".claude\skills"),
    $StateDirPath
)) { New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue | Out-Null }

if (-not $script:SkillsOnly) {
    foreach ($d in @(
        (Join-Path $script:ProjectDir "src\generated"),
        (Join-Path $script:ProjectDir "instruction-templates")
    )) { New-Item -ItemType Directory -Path $d -Force -ErrorAction SilentlyContinue | Out-Null }
}

Write-Ok "Workspace directories created"

# =============================================================================
# -- STEP 2: PREREQUISITES ----------------------------------------------------
# =============================================================================

Write-Step "Step 2 of 9 — Prerequisites"

if (-not $script:SkillsOnly) {

# git
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Ok "git $(& git --version 2>&1)"
} else {
    Write-Warn "git not found — installing via winget..."
    try {
        & winget install --id Git.Git --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command git -ErrorAction SilentlyContinue) {
            Write-Ok "git $(& git --version 2>&1) (just installed)"
        } else {
            Write-Warn "Git installed but not in PATH yet — restart terminal or install manually: https://git-scm.com"
        }
    } catch {
        Write-Die "git required. Install: https://git-scm.com"
    }
}

# npx / Node.js (needed for GitHub MCP + Atlassian MCP)
if (Get-Command npx -ErrorAction SilentlyContinue) {
    $nodeVer = & node --version 2>$null
    Write-Ok "Node.js $nodeVer / npx"
} else {
    Write-Warn "Node.js not found — installing via winget..."
    try {
        & winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        if (Get-Command npx -ErrorAction SilentlyContinue) {
            Write-Ok "Node.js $(& node --version 2>$null) / npx (just installed)"
        } else {
            Write-Warn "winget install Node.js succeeded but npx not in PATH yet — restart your terminal or install manually: https://nodejs.org"
        }
    } catch {
        Write-Warn "Could not auto-install Node.js — install manually: https://nodejs.org"
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

} # end SkillsOnly skip

# gh CLI (needed for GitHub MCP OAuth + SSH key setup)
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Write-Ok "gh CLI: $(& gh --version 2>&1 | Select-Object -First 1)"
} else {
    Write-Msg "gh CLI not found — installing..."

    # Try Scoop first (may fail on corporate proxies due to hash mismatch)
    Ensure-Scoop
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        & scoop update 2>&1 | Out-Null
        & scoop install gh 2>&1 | Out-Null
        Refresh-Path
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        # Scoop hash check failed (corporate SSL inspection rewrites downloads).
        # Extract directly from the zip — no installer, no admin required.
        Install-GhFromZip
    }

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Ok "gh CLI: $(& gh --version 2>&1 | Select-Object -First 1) (just installed)"
    } else {
        Write-Warn "Could not auto-install gh CLI — install manually: https://cli.github.com"
    }
}

# SSH access to GitHub (needed only when pulling enterprise skills from a remote git repo)
if ($EnterpriseSkillsMode -eq "git" -and $EnterpriseSkillsRepo) {

    # ── Dedicated McCain SSH key setup ────────────────────────────────────────
    # Uses %USERPROFILE%\.ssh\id_ed25519_mccain — created once, reused across all projects.
    # Updates ~/.ssh/config so SSH always picks this key for github.com.
    function Invoke-McCainSshKeySetup {
        $mccainKey     = Join-Path $env:USERPROFILE ".ssh\id_ed25519_mccain"
        $mccainKeyPub  = "$mccainKey.pub"
        $sshDir        = Join-Path $env:USERPROFILE ".ssh"
        New-Item -ItemType Directory -Path $sshDir -Force -ErrorAction SilentlyContinue | Out-Null

        # Step 1: Generate key only if it does not already exist
        if (-not (Test-Path $mccainKey)) {
            Write-Msg "Generating dedicated McCain SSH key..."
            $gitEmail   = try { if (Get-Command gh -ErrorAction SilentlyContinue) { & gh api user --jq '.email' 2>$null } } catch { "" }
            $keyComment = if ($gitEmail) { $gitEmail } else { "mccain-adk" }
            # PS 7+ passes empty string correctly; PS 5.x drops empty args to native exe so needs '""'
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                & ssh-keygen -t ed25519 -C $keyComment -f $mccainKey -N ""
            } else {
                & ssh-keygen -t ed25519 -C $keyComment -f $mccainKey -N '""'
            }
            if (Test-Path $mccainKey) {
                Write-Ok "McCain SSH key generated: $mccainKey"
            } else {
                Write-Die "ssh-keygen failed — could not generate key at $mccainKey"
            }
        } else {
            Write-Ok "Existing McCain SSH key found — reusing"
        }

        # Step 2: Register on GitHub only if not already there
        $localFp = if (Test-Path $mccainKeyPub) { (& ssh-keygen -lf $mccainKeyPub 2>$null) -split ' ' | Select-Object -Index 1 } else { "" }
        $ghKeys  = try { if (Get-Command gh -ErrorAction SilentlyContinue) { & gh ssh-key list 2>$null | Out-String } else { "" } } catch { "" }
        if ($localFp -and $ghKeys -match [regex]::Escape($localFp)) {
            Write-Ok "McCain SSH key already registered on GitHub"
        } elseif (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Warn "gh CLI not in PATH — SSH key generated but not registered on GitHub. Re-run after restarting your terminal."
        } else {
            $hostLabel = "Enterprise ADK - $env:COMPUTERNAME"
            Write-Msg "Registering McCain SSH key on GitHub..."
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $addErr = (& gh ssh-key add $mccainKeyPub --title $hostLabel 2>&1) | Out-String
            $addExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEap
            if ($addExit -eq 0 -or $addErr -match "already exists") {
                Write-Ok "McCain SSH key registered on GitHub ($hostLabel)"

                # Open GitHub SSH keys page so user can authorize the key for SAML SSO
                # (required if McCainFoods enforces SSO — cannot be automated via API)
                Write-Host ""
                Write-Warn "ACTION REQUIRED — SAML SSO authorization"
                Write-Msg  "  Opening your GitHub SSH keys page in the browser..."
                try { Start-Process "https://github.com/settings/keys" } catch {}
                Write-Msg  ""
                Write-Msg  "  In the browser:"
                Write-Msg  "    1. Find key:  `"$hostLabel`""
                Write-Msg  "    2. Click:     Configure SSO"
                Write-Msg  "    3. Click:     Authorize `"$EnterpriseOrg`""
                Write-Msg  ""
                Write-Msg  "  Skip this step only if $EnterpriseOrg does not enforce SAML SSO."
                Write-Host ""
                Read-Prompt "Press Enter once you have authorized the key (or to skip if SSO is not required)" "" | Out-Null
            } else {
                Write-Warn "Could not register SSH key: $($addErr.Trim())"
            }
        }

        # Step 3: Update %USERPROFILE%\.ssh\config to always use this key for github.com
        $sshConfig = Join-Path $sshDir "config"
        if (-not (Test-Path $sshConfig)) { New-Item -ItemType File -Path $sshConfig -Force | Out-Null }
        $content = Get-Content $sshConfig -Raw -ErrorAction SilentlyContinue
        if (-not $content) { $content = "" }
        $block = "`nHost github.com`n  IdentityFile $mccainKey`n  IdentitiesOnly yes`n"
        if ($content -match '(?m)^Host github\.com') {
            $content = $content -replace '(?ms)(^Host github\.com\r?\n)([ \t]+[^\r\n]*\r?\n)*', $block.TrimStart()
        } else {
            $content = $content.TrimEnd() + $block
        }
        Set-Content $sshConfig -Value $content -Encoding UTF8 -NoNewline
        Write-Ok "SSH config updated to use McCain key"

        # Step 4: Load key into ssh-agent for this session
        try {
            Start-Service ssh-agent -ErrorAction SilentlyContinue
            & ssh-add $mccainKey 2>$null
        } catch {}
    }

    # ── Check current SSH session ─────────────────────────────────────────────
    try { $sshOut = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) | Out-String } catch { $sshOut = "" }
    if ($sshOut -match "Hi ") {
        $ghUser = if ($sshOut -match "Hi ([^!]+)!") { $Matches[1].Trim() } else { "unknown" }
        Write-Ok "SSH access to github.com  (authenticated as: $ghUser)"
        $script:SkillsAuthMode = "ssh"

        # Confirm this is the correct McCain corporate account
        if (-not $script:Silent) {
            $confirm = Read-Prompt "Is '$ghUser' your McCain corporate GitHub account? (y/n)" "y"
            if ($confirm -notin @("y","Y")) {
                Write-Msg "Re-authenticating — please sign in with your McCain account in the browser..."
                try { & gh auth login --web --git-protocol https --scopes admin:public_key } catch {}
                try { & gh auth setup-git 2>$null } catch {}

                # Set up dedicated McCain SSH key for the newly authenticated account
                Invoke-McCainSshKeySetup

                # Re-test SSH with the new McCain key
                Write-Msg "Re-testing SSH access..."
                try { $sshOut = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) | Out-String } catch { $sshOut = "" }
                if ($sshOut -match "Hi ([^!]+)!") {
                    $ghUser = $Matches[1].Trim()
                    Write-Ok "Re-authenticated as: $ghUser"
                    $script:SkillsAuthMode = "ssh"
                } else {
                    Write-Warn "SSH not confirmed after re-auth — will use HTTPS with gh credentials"
                    $script:SkillsAuthMode = "https"
                }
            }
        }

    } else {
        Write-Warn "SSH access to github.com not verified"
        Write-Host ""
        $doSetup = Read-Prompt "Authenticate with GitHub to set up SSH keys automatically? (y/n)" "y"
        if ($doSetup -in @("y","Y")) {
            Write-Msg "Opening browser for GitHub authentication..."
            try { & gh auth login --web --git-protocol https --scopes admin:public_key } catch {}
            try { & gh auth setup-git 2>$null } catch {}

            # Set up dedicated McCain SSH key
            Invoke-McCainSshKeySetup

            # Re-test SSH
            Write-Msg "Re-testing SSH access..."
            try { $sshOut = (& ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) | Out-String } catch { $sshOut = "" }
            if ($sshOut -match "Hi ([^!]+)!") {
                $ghUser = $Matches[1].Trim()
                Write-Ok "SSH access to github.com verified  (authenticated as: $ghUser)"
                $script:SkillsAuthMode = "ssh"
            } else {
                Write-Warn "SSH not verified yet — will use HTTPS with gh credentials"
                $script:SkillsAuthMode = "https"
            }
        } else {
            Write-Msg "Skipped — enterprise skills will not be installed"
            Write-Msg "Re-run with:  .\enterprise_install.ps1 -SkillsOnly  after setting up GitHub authentication"
            $script:SkillsAuthMode = "skip"
        }
    }

    # ── Proactive repo access check ───────────────────────────────────────────
    if ($script:SkillsAuthMode -ne "skip" -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        & gh auth status 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $skillsRepoPath = $EnterpriseSkillsRepo -replace '^git@github\.com:', '' -replace '\.git$', ''
            Write-Msg "Checking access to enterprise skills repo..."
            & gh api "repos/$skillsRepoPath" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Enterprise skills repo accessible"
            } else {
                Write-Warn "Account '$ghUser' does not have access to: $EnterpriseSkillsRepo"
                Write-Msg  "  Contact your administrator to get access, then re-run:"
                Write-Msg  "    .\enterprise_install.ps1 -SkillsOnly"
                Write-Msg  "  Continuing with MCP and other setup..."
                $script:SkillsAuthMode = "skip"
            }
        }
    }
}

# =============================================================================
# -- STEP 3: DATABRICKS WORKSPACE & PROFILE -----------------------------------
# =============================================================================

if (-not $script:SkillsOnly) {

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
# Refresh PATH here in case Databricks CLI was just installed in Step 2 and wasn't in PATH yet
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

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
} else {
    Write-Warn "Databricks CLI not in PATH — skipping OAuth. After restarting your terminal, run:"
    Write-Msg  "  databricks auth login --host $($script:WorkspaceUrl) --profile $($script:Profile_)"
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

} # end SkillsOnly skip (Steps 3 + 4)

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
}

# =============================================================================
# -- STEP 6: GITHUB MCP -------------------------------------------------------
# =============================================================================

if (-not $script:SkillsOnly) {

Write-Step "Step 6 of 9 — GitHub MCP"

# -- Add GitHub entry to .mcp.json --------------------------------------------
$mcpJson = Get-Content $McpConfig -Raw | ConvertFrom-Json
$githubEnv = [PSCustomObject]@{ GITHUB_PERSONAL_ACCESS_TOKEN = $null }
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
        # Kill any leftover mcp-remote listener on the OAuth callback port (port 3736)
        # A previous installer run may have left a process holding the port.
        try { Get-NetTCPConnection -LocalPort 3736 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } } catch {}
        # Ensure NODE_EXTRA_CA_CERTS is available to the child process (handles --skills-only runs
        # where Step 4 was skipped but the value was persisted to the user environment in a prior run)
        if (-not $env:NODE_EXTRA_CA_CERTS) {
            $env:NODE_EXTRA_CA_CERTS = [System.Environment]::GetEnvironmentVariable("NODE_EXTRA_CA_CERTS", "User")
        }
        # Run mcp-remote as a PowerShell background job (same session context).
        # Do NOT use cmd.exe as a wrapper — Node's browser-open (cmd /c start <url>) fails
        # silently inside a detached cmd subprocess on corporate Windows.
        # Instead we poll for port 3736, then open the browser explicitly from THIS process
        # using Start-Process (ShellExecute), which always works on Windows.
        $atlCaCerts = $env:NODE_EXTRA_CA_CERTS
        $atlJob = Start-Job -ScriptBlock {
            if ($using:atlCaCerts) { $env:NODE_EXTRA_CA_CERTS = $using:atlCaCerts }
            & npx mcp-remote https://mcp.atlassian.com/v1/mcp --transport http-first 2>&1
        }
        # Poll for OAuth listener (port 3736) up to 15 seconds
        $atlWait = 0; $atlConn = $null
        while ($atlWait -lt 15) {
            Start-Sleep -Seconds 1; $atlWait++
            try { $atlConn = Get-NetTCPConnection -LocalPort 3736 -ErrorAction SilentlyContinue } catch { $atlConn = $null }
            if ($atlConn) { break }
        }
        # Explicitly open the browser from the main PowerShell process (reliable on Windows)
        if ($atlConn) {
            Write-Msg "Opening browser for Atlassian authentication..."
            try { Start-Process "http://localhost:3736" } catch {}
        } else {
            Write-Warn "mcp-remote listener did not start — try opening http://localhost:3736 manually"
        }
        Read-Prompt "Press Enter after completing Atlassian authentication in the browser" ""
        Stop-Job $atlJob -ErrorAction SilentlyContinue
        Remove-Job $atlJob -Force -ErrorAction SilentlyContinue
        Write-Ok "Atlassian MCP authenticated"
    } else {
        Write-Msg "Skipped — OAuth will prompt automatically on first MCP use."
        Write-Ok "Atlassian MCP configured"
    }
} else {
    Write-Warn "npx not found — Atlassian MCP OAuth skipped. Install Node.js first."
}

} # end SkillsOnly skip (Steps 6 + 7)

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

    # Helper: interpret git clone/fetch error and print an actionable message
    function Invoke-SkillsCloneError {
        param([string]$Err)
        if ($Err -match "repository not found|permission to .+ denied|403|access denied") {
            Write-Warn "Access denied to enterprise skills repo"
            Write-Msg  "  Your GitHub account does not have access to: $EnterpriseSkillsRepo"
            Write-Msg  "  Please ask your administrator to grant you access, then re-run:"
            Write-Msg  "    .\enterprise_install.ps1 -SkillsOnly"
        } elseif ($Err -match "permission denied.*publickey|could not read username|authentication failed") {
            Write-Warn "Authentication failed when cloning enterprise skills repo"
            Write-Msg  "  Re-run the installer to set up GitHub authentication again, or:"
            Write-Msg  "    .\enterprise_install.ps1 -SkillsOnly"
        } else {
            Write-Warn "Failed to clone enterprise skills repo"
            if ($Err) { Write-Msg "  Error: $Err" }
            Write-Msg  "  Re-run with -SkillsOnly after resolving the issue"
        }
    }

    if ($EnterpriseSkillsMode -eq "git") {
        if (-not $EnterpriseSkillsRepo) {
            Write-Warn "EnterpriseSkillsMode=git but EnterpriseSkillsRepo is empty — skipping"
        } elseif ($script:SkillsAuthMode -eq "skip") {
            Write-Warn "Enterprise skills skipped — GitHub authentication not set up"
            Write-Msg  "  Re-run with:  .\enterprise_install.ps1 -SkillsOnly  after setting up authentication"
        } else {
            # Pick clone URL based on auth mode set in Step 2
            $skillsCloneUrl = if ($script:SkillsAuthMode -eq "https") { $script:HttpsSkillsRepo } else { $EnterpriseSkillsRepo }

            if (Test-Path (Join-Path $EntSkillsRepoDir ".git")) {
                $currentRemote = & git -C $EntSkillsRepoDir remote get-url origin 2>$null
                if ($currentRemote -ne $skillsCloneUrl) {
                    Write-Msg "Enterprise skills repo URL changed — re-cloning..."
                    Remove-Item -Path $EntSkillsRepoDir -Recurse -Force
                    $cloneErr = (& git clone -q --depth 1 $skillsCloneUrl $EntSkillsRepoDir 2>&1) | Out-String
                    if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Invoke-SkillsCloneError $cloneErr }
                } else {
                    $fetchErr = (& git -C $EntSkillsRepoDir fetch -q --depth 1 origin HEAD 2>&1) | Out-String
                    if ($LASTEXITCODE -ne 0) {
                        Invoke-SkillsCloneError $fetchErr
                    } else {
                        $localChanges = (& git -C $EntSkillsRepoDir status --porcelain 2>$null) | Out-String
                        if ($localChanges.Trim()) { Write-Warn "Local modifications in enterprise skills repo discarded by update" }
                        try { & git -C $EntSkillsRepoDir reset --hard FETCH_HEAD 2>&1 | Out-Null } catch {}
                        if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Write-Warn "Failed to reset enterprise skills repo to latest" }
                    }
                }
            } else {
                New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction SilentlyContinue | Out-Null
                $cloneErr = (& git clone -q --depth 1 $skillsCloneUrl $EntSkillsRepoDir 2>&1) | Out-String
                if ($LASTEXITCODE -eq 0) { $entSource = $EntSkillsRepoDir } else { Invoke-SkillsCloneError $cloneErr }
            }
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
        Write-Ok "Enterprise skills  ($entCount installed)  ->  $skillsDest"
    } else {
        Write-Warn "No enterprise skills source found — skipping"
    }
}

# =============================================================================
# -- STEP 9: WORKSPACE + VERSION LOCK -----------------------------------------
# =============================================================================

if (-not $script:SkillsOnly) {

Write-Step "Step 9 of 9 — Workspace + Version Lock"

# -- .gitignore ---------------------------------------------------------------
$gitignore = Join-Path $script:ProjectDir ".gitignore"
if (-not (Test-Path $gitignore)) { New-Item -ItemType File -Path $gitignore -Force | Out-Null }
$giContent = Get-Content $gitignore -ErrorAction SilentlyContinue
foreach ($rule in @("$StateSubdir/", ".claude/", ".mcp.json", "src/generated/", ".databricks/", ".env", "__pycache__/", "*.pyc")) {
    if (-not ($giContent | Where-Object { $_.Trim() -ieq $rule })) { Add-Content $gitignore $rule }
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
        [PSCustomObject]$meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
    }
} else {
    [PSCustomObject]$meta | ConvertTo-Json -Depth 5 | Set-Content $metaFile -Encoding UTF8
}

$lock = [ordered]@{
    enterprise_adk       = "enterprise-install"
    enterprise_skills    = "bundled"
    databricks_workspace = $script:WorkspaceUrl
    installed_at         = $now
}
[PSCustomObject]$lock | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $StateDirPath "version.lock") -Encoding UTF8

Write-Ok "$StateSubdir/metadata.json"
Write-Ok "$StateSubdir/version.lock"

} # end SkillsOnly skip (Step 9)

# =============================================================================
# -- SUMMARY ------------------------------------------------------------------
# =============================================================================

Write-Host ""
if ($script:SkillsOnly) {
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   ✓  Skills Updated                                    ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  {0,-20} {1}" -f "Project",           $script:ProjectDir)
    Write-Host ("  {0,-20} {1}" -f "Databricks skills", "$dbCount installed")
    Write-Host ("  {0,-20} {1}" -f "Enterprise skills", "$entCount installed")
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open your project in Claude Code:  claude $($script:ProjectDir)" -ForegroundColor Cyan
    Write-Host "  2. Skills are active — try: `"List my SQL warehouses`""
} else {
    Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║   ✓  Workspace Ready                                   ║" -ForegroundColor Green
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
}
Write-Host ""
