# Mole Windows - Path Protection
# System critical and data-protected application lists

#Requires -Version 5.1

# Import dependencies
$basePath = Join-Path $PSScriptRoot "Base.psm1"
$logPath = Join-Path $PSScriptRoot "Log.psm1"
if (-not (Get-Module -Name "Base" -ErrorAction SilentlyContinue)) {
    Import-Module $basePath -Force -DisableNameChecking
}
if (-not (Get-Module -Name "Log" -ErrorAction SilentlyContinue)) {
    Import-Module $logPath -Force -DisableNameChecking
}

# Prevent multiple loading
if ($script:MOLE_PATH_PROTECTION_LOADED) { return }
$script:MOLE_PATH_PROTECTION_LOADED = $true

# ============================================================================
# Critical System Paths (NEVER delete)
# ============================================================================
$script:CRITICAL_SYSTEM_PATHS = @(
    # Windows System Directories
    $env:SystemRoot                                    # C:\Windows
    "$env:SystemRoot\System32"
    "$env:SystemRoot\SysWOW64"
    "$env:SystemRoot\WinSxS"
    "$env:SystemDrive\Recovery"
    "$env:SystemDrive\Program Files"
    "$env:SystemDrive\Program Files (x86)"
    "$env:ProgramFiles"
    "${env:ProgramFiles(x86)}"
    "$env:SystemRoot\Boot"
    "$env:SystemRoot\Fonts"
    "$env:SystemRoot\INF"
    "$env:SystemRoot\PolicyDefinitions"
    "$env:SystemRoot\Security"
    "$env:SystemRoot\servicing"
    "$env:SystemRoot\SoftwareDistribution\DataStore"  # Allow Download cleanup but not DataStore

    # User Profile Protected Directories
    "$env:USERPROFILE\Documents"
    "$env:USERPROFILE\Pictures"
    "$env:USERPROFILE\Videos"
    "$env:USERPROFILE\Music"
    "$env:USERPROFILE\Desktop"
    "$env:USERPROFILE\Downloads"                       # Don't auto-clean downloads

    # Critical Application Data
    "$env:APPDATA\Microsoft\Windows\Start Menu"
    "$env:APPDATA\Microsoft\Windows\SendTo"
    "$env:APPDATA\Microsoft\Windows\Templates"
    "$env:APPDATA\Microsoft\Credentials"
    "$env:LOCALAPPDATA\Microsoft\Credentials"
    "$env:APPDATA\Microsoft\Crypto"
    "$env:APPDATA\Microsoft\Protect"
    "$env:APPDATA\Microsoft\SystemCertificates"
)

# ============================================================================
# Protected Application Patterns (data protection during cleanup)
# ============================================================================
$script:DATA_PROTECTED_PATTERNS = @(
    # Password Managers & Security
    "*1password*"
    "*LastPass*"
    "*Dashlane*"
    "*Bitwarden*"
    "*KeePass*"
    "*Authy*"
    "*YubiKey*"

    # Development IDEs & Editors (settings/workspace data)
    "*JetBrains*"
    "*IntelliJ*"
    "*PyCharm*"
    "*WebStorm*"
    "*GoLand*"
    "*DataGrip*"
    "*Rider*"
    "*CLion*"
    "*PhpStorm*"
    "*RubyMine*"
    "*Code\User*"                # VS Code user settings
    "*Code\Workspaces*"          # VS Code workspaces
    "*Sublime Text*"
    "*Sublime Merge*"

    # AI & LLM Tools
    "*Claude*"
    "*ChatGPT*"
    "*Ollama*"
    "*LM Studio*"
    "*Cursor*"

    # Database Clients (connection configs)
    "*TablePlus*"
    "*DBeaver*"
    "*Navicat*"
    "*MongoDB Compass*"
    "*Redis*"
    "*pgAdmin*"
    "*HeidiSQL*"
    "*Azure Data Studio*"

    # API & Network Tools
    "*Postman*"
    "*Insomnia*"
    "*Fiddler*"
    "*Charles*"
    "*Proxyman*"

    # Git & Version Control
    "*GitHub Desktop*"
    "*SourceTree*"
    "*GitKraken*"
    "*Tower*"
    "*Fork*"

    # Terminals
    "*Windows Terminal*"
    "*Hyper*"
    "*Alacritty*"
    "*WezTerm*"
    "*Tabby*"

    # Docker & Virtualization
    "*Docker*"
    "*VirtualBox*"
    "*VMware*"
    "*Hyper-V*"
    "*WSL*"

    # VPN & Proxy (sensitive configs)
    "*NordVPN*"
    "*ExpressVPN*"
    "*ProtonVPN*"
    "*OpenVPN*"
    "*WireGuard*"
    "*Tailscale*"
    "*Cloudflare*"

    # Cloud Storage
    "*OneDrive*"
    "*Dropbox*"
    "*Google Drive*"
    "*iCloud*"
    "*Box*"
    "*pCloud*"

    # Communication
    "*Discord*"
    "*Slack*"
    "*Teams*"
    "*Zoom*"
    "*Telegram*"
    "*WhatsApp*"
    "*Signal*"

    # Note-Taking & Documentation
    "*Obsidian*"
    "*Notion*"
    "*Logseq*"
    "*Evernote*"
    "*OneNote*"
    "*Typora*"
    "*Roam*"

    # Design Tools
    "*Adobe*"
    "*Figma*"
    "*Sketch*"
    "*Affinity*"
    "*Canva*"

    # Media (library data)
    "*Spotify*"
    "*VLC*"
    "*iTunes*"
    "*Plex*"

    # Backup & Sync
    "*Backblaze*"
    "*Acronis*"
    "*Veeam*"
    "*Carbonite*"

    # Browser Profiles (not cache)
    "*Chrome\User Data\Default\Bookmarks*"
    "*Chrome\User Data\Default\Preferences*"
    "*Chrome\User Data\Default\Login Data*"
    "*Edge\User Data\Default\Bookmarks*"
    "*Edge\User Data\Default\Preferences*"
    "*Edge\User Data\Default\Login Data*"
    "*Firefox\Profiles*"
    "*Brave*\User Data\Default\Bookmarks*"
)

# ============================================================================
# Safe Cache Directories (can be cleaned)
# ============================================================================
$script:SAFE_CACHE_PATTERNS = @(
    # Windows Temp
    "$env:TEMP\*"
    "$env:LOCALAPPDATA\Temp\*"
    "$env:SystemRoot\Temp\*"

    # Browser Caches (not profiles)
    "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache*"
    "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache*"
    "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache*"
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache*"
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache*"
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache*"

    # Windows Caches
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*"
    "$env:LOCALAPPDATA\Microsoft\Windows\WebCache\*"
    "$env:LOCALAPPDATA\Microsoft\Windows\Caches\*"

    # Windows Update (download cache only)
    "$env:SystemRoot\SoftwareDistribution\Download\*"

    # Windows Error Reports
    "$env:LOCALAPPDATA\Microsoft\Windows\WER\*"
    "$env:ProgramData\Microsoft\Windows\WER\*"

    # Package Manager Caches
    "$env:LOCALAPPDATA\npm-cache\*"
    "$env:LOCALAPPDATA\pip\Cache\*"
    "$env:LOCALAPPDATA\NuGet\v3-cache\*"
    "$env:USERPROFILE\.cargo\registry\cache\*"
    "$env:USERPROFILE\.gradle\caches\*"
    "$env:USERPROFILE\.m2\repository\*"

    # Electron App Caches
    "*\Cache\*"
    "*\CachedData\*"
    "*\GPUCache\*"
    "*\Code Cache\*"
    "*\DawnWebGPUCache\*"
    "*\DawnGraphiteCache\*"
)

# ============================================================================
# Protection Functions
# ============================================================================

function Test-IsCriticalSystemPath {
    <#
    .SYNOPSIS
        Checks if a path is a critical system directory that must never be deleted.
    .PARAMETER Path
        The path to check.
    .OUTPUTS
        Boolean indicating if path is critical.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Normalize path
    $normalizedPath = $Path.TrimEnd('\', '/').ToLower()

    foreach ($criticalPath in $script:CRITICAL_SYSTEM_PATHS) {
        if (-not $criticalPath) { continue }

        $normalizedCritical = $criticalPath.TrimEnd('\', '/').ToLower()

        # Exact match
        if ($normalizedPath -eq $normalizedCritical) {
            return $true
        }

        # Check if it's a parent of critical path (we shouldn't delete parents either)
        if ($normalizedCritical.StartsWith("$normalizedPath\")) {
            return $true
        }
    }

    # Check for Windows system root patterns
    $systemRootLower = $env:SystemRoot.ToLower()
    if ($normalizedPath -eq $systemRootLower -or
        $normalizedPath.StartsWith("$systemRootLower\system32") -or
        $normalizedPath.StartsWith("$systemRootLower\syswow64") -or
        $normalizedPath.StartsWith("$systemRootLower\winsxs")) {
        return $true
    }

    # Check for Program Files
    $progFilesLower = $env:ProgramFiles.ToLower()
    $progFiles86Lower = ${env:ProgramFiles(x86)}.ToLower()
    if ($normalizedPath -eq $progFilesLower -or $normalizedPath -eq $progFiles86Lower) {
        return $true
    }

    return $false
}

function Test-IsProtectedData {
    <#
    .SYNOPSIS
        Checks if a path contains protected application data.
    .PARAMETER Path
        The path to check.
    .OUTPUTS
        Boolean indicating if path is protected.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    foreach ($pattern in $script:DATA_PROTECTED_PATTERNS) {
        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

function Test-IsSafeToClean {
    <#
    .SYNOPSIS
        Checks if a path is safe to clean (matches known cache patterns).
    .PARAMETER Path
        The path to check.
    .OUTPUTS
        Boolean indicating if path is safe to clean.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # First check if it's critical or protected
    if (Test-IsCriticalSystemPath -Path $Path) {
        return $false
    }

    if (Test-IsProtectedData -Path $Path) {
        return $false
    }

    # Check if it matches safe cache patterns
    foreach ($pattern in $script:SAFE_CACHE_PATTERNS) {
        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

function Test-ShouldProtectPath {
    <#
    .SYNOPSIS
        Master function to check if a path should be protected from deletion.
    .PARAMETER Path
        The path to check.
    .OUTPUTS
        Boolean - $true if path should be protected, $false if safe to delete.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Empty path - protect
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $true
    }

    # Critical system paths - always protect
    if (Test-IsCriticalSystemPath -Path $Path) {
        Write-MoleDebug "Protected (critical system): $Path"
        return $true
    }

    # Protected application data - protect
    if (Test-IsProtectedData -Path $Path) {
        Write-MoleDebug "Protected (app data): $Path"
        return $true
    }

    # User profile root - protect
    $userProfileLower = $env:USERPROFILE.ToLower()
    $pathLower = $Path.ToLower().TrimEnd('\', '/')

    if ($pathLower -eq $userProfileLower) {
        return $true
    }

    return $false
}

function Get-CriticalPaths {
    <#
    .SYNOPSIS
        Returns the list of critical system paths.
    #>
    return $script:CRITICAL_SYSTEM_PATHS
}

function Get-ProtectedPatterns {
    <#
    .SYNOPSIS
        Returns the list of protected data patterns.
    #>
    return $script:DATA_PROTECTED_PATTERNS
}

function Get-SafeCachePatterns {
    <#
    .SYNOPSIS
        Returns the list of safe cache patterns.
    #>
    return $script:SAFE_CACHE_PATTERNS
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Test-IsCriticalSystemPath'
    'Test-IsProtectedData'
    'Test-IsSafeToClean'
    'Test-ShouldProtectPath'
    'Get-CriticalPaths'
    'Get-ProtectedPatterns'
    'Get-SafeCachePatterns'
)
