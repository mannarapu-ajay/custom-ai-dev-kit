#Requires -Version 5.1
<#
.SYNOPSIS
    McCain Enterprise Dev Environment Setup (Windows)

.DESCRIPTION
    Checks and installs the following prerequisites:
      1. Git  - with McCain GitHub authentication, SSH key generation, and SAML SSO
      2. uv   - Python package / project manager (astral.sh)
      3. Node.js / npx

.USAGE
    powershell -ExecutionPolicy Bypass -File setup.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Run a native command, capture all output (stdout + stderr merged), and return
# the combined output as a string. Never throws on non-zero exit codes.
# Works on both Windows PowerShell 5.1 and PowerShell 7+.
function Invoke-Native {
    param([scriptblock]$Cmd)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $Cmd 2>&1
        return ($out | ForEach-Object { "$_" }) -join "`n"
    } finally {
        $ErrorActionPreference = $prev
    }
}

# =============================================================================
# -- CONFIGURATION ------------------------------------------------------------
# =============================================================================

$ENTERPRISE_ORG = "McCainFoods"
$MCCAIN_SSH_KEY = "$HOME\.ssh\id_ed25519_mccain"

# =============================================================================
# -- OUTPUT HELPERS -----------------------------------------------------------
# =============================================================================

function msg  { param([string]$Text) Write-Host "  $Text" }
function ok   { param([string]$Text) Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host " $Text" }
function warn { param([string]$Text) Write-Host "  " -NoNewline; Write-Host "!" -ForegroundColor Yellow -NoNewline; Write-Host " $Text" }
function die  { param([string]$Text) Write-Host "  " -NoNewline; Write-Host "X" -ForegroundColor Red -NoNewline; Write-Host " $Text"; exit 1 }

function step {
    param([string]$Text)
    $line = "-" * 56
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function prompt_input {
    param([string]$Text, [string]$Default = "")
    $display = if ($Default) { "$Text [$Default]" } else { $Text }
    Write-Host "  ${display}: " -NoNewline
    $result = Read-Host
    if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
    return $result
}

function command_exists {
    param([string]$Cmd)
    return [bool](Get-Command $Cmd -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath    = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH    = "$machinePath;$userPath"
}

# =============================================================================
# -- SCOOP (Windows package manager) ------------------------------------------
# =============================================================================

function Ensure-Scoop {
    if (command_exists "scoop") { return }

    msg "Scoop not found -- installing..."
    try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue } catch {}
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Refresh-Path

    if (command_exists "scoop") {
        ok "Scoop installed"
    } else {
        die "Scoop installation failed. Install manually: https://scoop.sh"
    }
}

# =============================================================================
# -- STEP 1: GIT --------------------------------------------------------------
# =============================================================================

step "Step 1 of 3 - Git"

if (command_exists "git") {
    ok "Git already installed  ($(git --version))"
} else {
    msg "Git not found -- installing via Scoop..."
    Ensure-Scoop
    scoop update
    scoop install git
    Refresh-Path
    if (command_exists "git") {
        ok "Git installed  ($(git --version))"
    } else {
        die "Git installation failed."
    }
}

# -- GitHub CLI (gh) - required for auth and SSH key registration -------------

function Install-GhFromZip {
    # Extracts gh directly to the user profile -- no admin, no installer required.
    # This is the reliable path on corporate machines where proxies break Scoop hashes
    # and winget MSI installers require elevation.
    msg "Installing gh CLI via direct ZIP extraction (no admin required)..."

    $ghDir  = "$env:USERPROFILE\AppData\Local\Programs\gh"
    $tmpZip = "$env:TEMP\gh_windows_amd64.zip"
    $tmpDir = "$env:TEMP\gh_extract"

    # Resolve latest release download URL via GitHub API
    $downloadUrl = $null
    try {
        $release     = Invoke-RestMethod -Uri "https://api.github.com/repos/cli/cli/releases/latest" -UseBasicParsing
        $asset       = $release.assets | Where-Object { $_.name -like "*windows_amd64.zip" } | Select-Object -First 1
        $downloadUrl = $asset.browser_download_url
        msg "Latest gh release: $($release.tag_name)"
    } catch {
        # Fallback to a known stable version
        $downloadUrl = "https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_windows_amd64.zip"
        msg "Could not query GitHub API -- using fallback version"
    }

    msg "Downloading gh..."
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpZip -UseBasicParsing

    if (Test-Path $tmpDir)  { Remove-Item $tmpDir  -Recurse -Force }
    if (Test-Path $ghDir)   { Remove-Item $ghDir   -Recurse -Force }

    New-Item -ItemType Directory -Path $ghDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

    # The zip contains a versioned subdirectory; find gh.exe and copy its parent contents
    $ghExe = Get-ChildItem -Path $tmpDir -Filter "gh.exe" -Recurse | Select-Object -First 1
    if (-not $ghExe) { die "gh.exe not found in downloaded archive." }
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

if (command_exists "gh") {
    ok "GitHub CLI already installed  ($(gh --version | Select-Object -First 1))"
} else {
    msg "GitHub CLI (gh) not found -- installing..."

    # Try Scoop first (may fail on corporate proxies due to hash mismatch)
    Ensure-Scoop
    scoop update
    & scoop install gh 2>&1 | Out-Null
    Refresh-Path

    if (-not (command_exists "gh")) {
        # Scoop hash check failed (corporate SSL inspection rewrites downloads).
        # Extract directly from the zip -- no installer, no admin required.
        Install-GhFromZip
    }

    if (command_exists "gh") {
        ok "GitHub CLI installed  ($(gh --version | Select-Object -First 1))"
    } else {
        die "GitHub CLI installation failed. Install manually: https://cli.github.com"
    }
}

# -- Git global config (name / email) -----------------------------------------

function Configure-GitIdentity {
    $currentName  = (git config --global user.name  2>$null) -join ""
    $currentEmail = (git config --global user.email 2>$null) -join ""

    if ([string]::IsNullOrWhiteSpace($currentName) -or [string]::IsNullOrWhiteSpace($currentEmail)) {
        try {
            $ghName  = (gh api user --jq '.name'  2>$null) -join ""
            $ghEmail = (gh api user --jq '.email' 2>$null) -join ""
            if ([string]::IsNullOrWhiteSpace($currentName))  { $currentName  = $ghName  }
            if ([string]::IsNullOrWhiteSpace($currentEmail)) { $currentEmail = $ghEmail }
        } catch {}
    }

    $defaultName  = if ($currentName)  { $currentName }  else { "First Last" }
    $defaultEmail = if ($currentEmail) { $currentEmail } else { "yourname@mccain.ca" }

    $name  = prompt_input "Full name for git config" $defaultName
    $email = prompt_input "McCain email for git config (e.g. first.last@mccain.ca)" $defaultEmail

    git config --global user.name          $name
    git config --global user.email         $email
    git config --global push.default       current
    git config --global pull.rebase        true
    git config --global init.defaultBranch main
    git config --global core.autocrlf      true

    ok "Git identity configured  ($name <$email>)"
}

# -- SSH key helper -----------------------------------------------------------

function Check-SSHGitHub {
    try {
        $out = & ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1
        return ($out -join " ")
    } catch {
        return ""
    }
}

function Setup-McCainSSHKey {
    $sshDir = "$HOME\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # 1. Generate key (skip if already exists)
    if (-not (Test-Path $MCCAIN_SSH_KEY)) {
        msg "Generating McCain SSH key (ed25519)..."
        $gitEmail = ""
        try { $gitEmail = (gh api user --jq '.email' 2>$null) -join "" } catch {}
        if ([string]::IsNullOrWhiteSpace($gitEmail)) {
            try { $gitEmail = (git config --global user.email 2>$null) -join "" } catch {}
        }
        if ([string]::IsNullOrWhiteSpace($gitEmail)) { $gitEmail = "mccain-setup" }

        & ssh-keygen -t ed25519 -C $gitEmail -f $MCCAIN_SSH_KEY -N '""'
        ok "SSH key generated: $MCCAIN_SSH_KEY"
    } else {
        ok "Existing McCain SSH key found -- reusing  ($MCCAIN_SSH_KEY)"
    }

    # 2. Register on GitHub (skip if fingerprint already present)
    $pubKeyFile = "${MCCAIN_SSH_KEY}.pub"
    $localFp = ""
    try {
        $fpLine  = (& ssh-keygen -lf $pubKeyFile 2>$null) -join " "
        $localFp = ($fpLine -split "\s+")[1]
    } catch {}

    $alreadyRegistered = $false
    if ($localFp) {
        try {
            $keyList = (gh ssh-key list 2>$null) -join " "
            $alreadyRegistered = $keyList -like "*$localFp*"
        } catch {}
    }

    if ($alreadyRegistered) {
        ok "SSH key already registered on GitHub"
    } else {
        $hostLabel = "McCain Enterprise Setup - $env:COMPUTERNAME"
        msg "Registering SSH key on GitHub..."
        $ghAddOut = Invoke-Native { gh ssh-key add $pubKeyFile --title $hostLabel }
        $ghAddExit = $LASTEXITCODE
        # "already exists" is also a success
        if ($ghAddExit -eq 0 -or $ghAddOut -match "already exists") {
            ok "SSH key registered on GitHub  ($hostLabel)"

            Write-Host ""
            warn "ACTION REQUIRED - SAML SSO authorization"
            msg "  Opening GitHub SSH keys page in your browser..."
            Start-Process "https://github.com/settings/keys"

            Write-Host ""
            msg "  In your browser:"
            msg "    1. Find key:  `"$hostLabel`""
            msg "    2. Click:     Configure SSO"
            msg "    3. Click:     Authorize  `"$ENTERPRISE_ORG`""
            Write-Host ""
            msg "  Skip if $ENTERPRISE_ORG does not enforce SAML SSO."
            Write-Host ""
            prompt_input "Press Enter once you have authorized the key (or to skip)" "" | Out-Null
        } else {
            warn "Could not auto-register SSH key -- add it manually at https://github.com/settings/keys"
            msg "  Public key:"
            msg "  $(Get-Content $pubKeyFile -Raw)"
        }
    }

    # 3. Update ~/.ssh/config to always use this key for github.com
    $sshConfig = "$sshDir\config"
    if (-not (Test-Path $sshConfig)) {
        New-Item -ItemType File -Path $sshConfig -Force | Out-Null
    }

    $configContent = Get-Content $sshConfig -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($configContent)) { $configContent = "" }

    $newBlock = "`nHost github.com`n  IdentityFile $MCCAIN_SSH_KEY`n  IdentitiesOnly yes`n"

    if ($configContent -notmatch "Host github\.com") {
        Add-Content -Path $sshConfig -Value $newBlock
    } else {
        $updated = $configContent -replace "(?s)`nHost github\.com`n(?:[ `t]+[^`n]*`n)*", $newBlock
        Set-Content -Path $sshConfig -Value $updated -NoNewline
    }
    ok "~/.ssh/config updated to use McCain key for github.com"

    # 4. Load key into ssh-agent for this session
    try {
        $sshAgent = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
        if ($sshAgent -and $sshAgent.Status -ne "Running") {
            Start-Service ssh-agent -ErrorAction SilentlyContinue
        }
        & ssh-add $MCCAIN_SSH_KEY 2>$null
    } catch {}
}

# -- Main GitHub authentication flow ------------------------------------------

function Authenticate-GitHub {
    $sshOut = Check-SSHGitHub

    if ($sshOut -match "Hi (\S+)!") {
        $ghUser = $Matches[1]
        ok "Already authenticated with GitHub  ($ghUser)"

        $confirm = prompt_input "Is '$ghUser' your McCain corporate GitHub account? (y/n)" "y"
        if ($confirm -eq "y" -or $confirm -eq "Y") {
            Configure-GitIdentity
            Setup-McCainSSHKey
            return
        }

        msg "Re-authenticating with your McCain account..."
    } else {
        msg "Not authenticated with GitHub -- opening browser..."
    }

    $ErrorActionPreference = "Continue"
    & gh auth login --web --git-protocol https --scopes admin:public_key
    & gh auth setup-git 2>$null
    $ErrorActionPreference = "Stop"

    Configure-GitIdentity
    Setup-McCainSSHKey

    # Verify SSH after setup
    msg "Verifying SSH access..."
    $sshOut = Check-SSHGitHub
    if ($sshOut -match "Hi (\S+)!") {
        $ghUser = $Matches[1]
        ok "SSH access to github.com confirmed  (authenticated as: $ghUser)"
    } else {
        warn "SSH access could not be verified -- you may need to add the key manually."
        $pubKeyPath = "${MCCAIN_SSH_KEY}.pub"
        $pubKey = if (Test-Path $pubKeyPath) { Get-Content $pubKeyPath -Raw } else { "Key not found" }
        msg "  Public key: $pubKey"
        msg "  Go to: https://github.com/settings/keys"
    }
}

Authenticate-GitHub

# =============================================================================
# -- STEP 2: UV ---------------------------------------------------------------
# =============================================================================

step "Step 2 of 3 - uv (Python package manager)"

if (command_exists "uv") {
    ok "uv already installed  ($(uv --version))"
} else {
    msg "uv not found -- installing..."
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    Refresh-Path

    # Also probe common install locations
    $uvPaths = @(
        "$env:USERPROFILE\.local\bin",
        "$env:USERPROFILE\.cargo\bin",
        "$env:APPDATA\uv\bin"
    )
    foreach ($p in $uvPaths) {
        if (Test-Path "$p\uv.exe") {
            $env:PATH = "$p;" + $env:PATH
            break
        }
    }

    if (command_exists "uv") {
        ok "uv installed  ($(uv --version))"
    } else {
        warn "uv installed but not in current PATH. Restart your terminal or add to PATH manually."
    }
}

# =============================================================================
# -- STEP 3: NODE.JS / NPX ----------------------------------------------------
# =============================================================================

step "Step 3 of 3 - Node.js / npx"

if ((command_exists "node") -and (command_exists "npx")) {
    ok "Node.js already installed  ($(node --version))"
    ok "npx available  ($(npx --version))"
} else {
    msg "Node.js not found -- installing via Scoop..."
    Ensure-Scoop
    scoop update
    scoop install nodejs-lts
    Refresh-Path
    if ((command_exists "node") -and (command_exists "npx")) {
        ok "Node.js installed  ($(node --version))"
        ok "npx available  ($(npx --version))"
    } else {
        die "Node.js installation failed. Install manually: https://nodejs.org"
    }
}

# =============================================================================
# -- SUMMARY ------------------------------------------------------------------
# =============================================================================

Write-Host ""
Write-Host ("=" * 56) -ForegroundColor Cyan
Write-Host "  " -NoNewline; Write-Host "Setup complete!" -ForegroundColor Green
Write-Host ("=" * 56) -ForegroundColor Cyan
Write-Host ""

$gitVer  = if (command_exists "git")  { git --version }  else { "see above" }
$uvVer   = if (command_exists "uv")   { uv --version }   else { "restart terminal to activate" }
$nodeVer = if (command_exists "node") { node --version } else { "see above" }
$npxVer  = if (command_exists "npx")  { npx --version }  else { "see above" }

Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host " Git     $gitVer"
Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host " uv      $uvVer"
Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host " Node    $nodeVer"
Write-Host "  " -NoNewline; Write-Host "OK" -ForegroundColor Green -NoNewline; Write-Host " npx     $npxVer"
Write-Host ""
Write-Host "  " -NoNewline
Write-Host "Note:" -ForegroundColor Yellow -NoNewline
Write-Host " If uv is not found in a new terminal, add its bin dir to your PATH:"
Write-Host '        $env:PATH = "$env:USERPROFILE\.local\bin;" + $env:PATH'
Write-Host ""
