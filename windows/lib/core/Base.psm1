# Mole Windows - Base Definitions and Utilities
# Core definitions, constants, and basic utility functions used by all modules

#Requires -Version 5.1

# Prevent multiple loading
if ($script:MOLE_BASE_LOADED) { return }
$script:MOLE_BASE_LOADED = $true

# ============================================================================
# Color Definitions (ANSI escape codes for PowerShell 5.1+ compatibility)
# ============================================================================
$script:ESC = [char]27
$script:GREEN = "$ESC[0;32m"
$script:BLUE = "$ESC[0;34m"
$script:CYAN = "$ESC[0;36m"
$script:YELLOW = "$ESC[0;33m"
$script:PURPLE = "$ESC[0;35m"
$script:PURPLE_BOLD = "$ESC[1;35m"
$script:RED = "$ESC[0;31m"
$script:GRAY = "$ESC[0;90m"
$script:NC = "$ESC[0m"

# ============================================================================
# Icon Definitions
# ============================================================================
$script:ICON_CONFIRM = [char]0x25CE   # ◎
$script:ICON_ADMIN = [char]0x2699     # ⚙
$script:ICON_SUCCESS = [char]0x2713   # ✓
$script:ICON_ERROR = [char]0x263B     # ☻
$script:ICON_WARNING = [char]0x25CF   # ●
$script:ICON_EMPTY = [char]0x25CB     # ○
$script:ICON_SOLID = [char]0x25CF     # ●
$script:ICON_LIST = [char]0x2022      # •
$script:ICON_ARROW = [char]0x27A4     # ➤
$script:ICON_DRY_RUN = [char]0x2192   # →
$script:ICON_NAV_UP = [char]0x2191    # ↑
$script:ICON_NAV_DOWN = [char]0x2193  # ↓

# ============================================================================
# Global Configuration Constants
# ============================================================================
$script:MOLE_TEMP_FILE_AGE_DAYS = 7        # Temp file retention (days)
$script:MOLE_ORPHAN_AGE_DAYS = 60          # Orphaned data retention (days)
$script:MOLE_MAX_PARALLEL_JOBS = 15        # Parallel job limit
$script:MOLE_LOG_AGE_DAYS = 7              # Log retention (days)
$script:MOLE_CRASH_REPORT_AGE_DAYS = 7     # Crash report retention (days)
$script:MOLE_SAVED_STATE_AGE_DAYS = 30     # Saved state retention (days)
$script:MOLE_MAX_DS_STORE_FILES = 500      # Max metadata files per scan

# ============================================================================
# Path Definitions (Windows equivalents)
# ============================================================================
$script:MOLE_CONFIG_DIR = Join-Path $env:LOCALAPPDATA "mole"
$script:MOLE_LOG_FILE = Join-Path $script:MOLE_CONFIG_DIR "mole.log"
$script:MOLE_DEBUG_LOG_FILE = Join-Path $script:MOLE_CONFIG_DIR "mole_debug_session.log"
$script:MOLE_WHITELIST_FILE = Join-Path $script:MOLE_CONFIG_DIR "whitelist"

# ============================================================================
# Whitelist Configuration
# ============================================================================
$script:DEFAULT_WHITELIST_PATTERNS = @(
    # Browser profiles (not just cache)
    "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Bookmarks*"
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Bookmarks*"
    # Development tools
    "$env:LOCALAPPDATA\JetBrains*"
    "$env:APPDATA\JetBrains*"
    # Cloud sync
    "$env:LOCALAPPDATA\Microsoft\OneDrive*"
    "$env:LOCALAPPDATA\Dropbox*"
    # AI/ML models
    "$env:USERPROFILE\.ollama\models*"
    "$env:USERPROFILE\.cache\huggingface*"
)

# ============================================================================
# Utility Functions
# ============================================================================

function Get-MoleConfigDir {
    <#
    .SYNOPSIS
        Returns the Mole configuration directory path.
    #>
    return $script:MOLE_CONFIG_DIR
}

function Ensure-MoleConfigDir {
    <#
    .SYNOPSIS
        Ensures the Mole configuration directory exists.
    #>
    if (-not (Test-Path $script:MOLE_CONFIG_DIR)) {
        New-Item -Path $script:MOLE_CONFIG_DIR -ItemType Directory -Force | Out-Null
    }
}

function Get-FreeSpace {
    <#
    .SYNOPSIS
        Gets free disk space on the system drive.
    .OUTPUTS
        String with human-readable disk space.
    #>
    param(
        [string]$DriveLetter = $env:SystemDrive.Substring(0, 1)
    )

    try {
        $drive = Get-PSDrive -Name $DriveLetter -ErrorAction Stop
        return Format-ByteSize -Bytes $drive.Free
    }
    catch {
        return "Unknown"
    }
}

function Format-ByteSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable format.
    .PARAMETER Bytes
        The size in bytes to convert.
    .OUTPUTS
        String like "1.5GB", "256MB", etc.
    #>
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return "{0:N2}GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N1}MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N0}KB" -f ($Bytes / 1KB)
    }
    else {
        return "{0}B" -f $Bytes
    }
}

function Get-PathSize {
    <#
    .SYNOPSIS
        Gets the size of a file or directory in bytes.
    .PARAMETER Path
        The path to measure.
    .OUTPUTS
        Size in bytes, or 0 if path doesn't exist.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return 0
    }

    try {
        $item = Get-Item $Path -Force -ErrorAction Stop
        if ($item.PSIsContainer) {
            $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            return [long]($(if ($null -eq $size) { 0 } else { $size }))
        }
        else {
            return [long]$item.Length
        }
    }
    catch {
        return 0
    }
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if the current session has administrator privileges.
    .OUTPUTS
        Boolean indicating admin status.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsInteractive {
    <#
    .SYNOPSIS
        Checks if running in an interactive terminal.
    .OUTPUTS
        Boolean indicating interactive status.
    #>
    return [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
}

function Get-OptimalParallelJobs {
    <#
    .SYNOPSIS
        Gets optimal parallel job count based on operation type.
    .PARAMETER OperationType
        Type of operation: scan, io, compute, or default.
    #>
    param(
        [ValidateSet("scan", "io", "compute", "default")]
        [string]$OperationType = "default"
    )

    $cpuCores = [Environment]::ProcessorCount

    switch ($OperationType) {
        "scan"    { return $cpuCores * 2 }
        "io"      { return $cpuCores * 2 }
        "compute" { return $cpuCores }
        default   { return $cpuCores + 2 }
    }
}

function Get-WindowsVersion {
    <#
    .SYNOPSIS
        Gets Windows version information.
    .OUTPUTS
        Hashtable with Major, Minor, Build, and DisplayVersion.
    #>
    $os = Get-CimInstance Win32_OperatingSystem
    $version = [System.Environment]::OSVersion.Version

    # Get display version (like 22H2) from registry
    $displayVersion = try {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion -ErrorAction Stop).DisplayVersion
    } catch {
        "Unknown"
    }

    return @{
        Major = $version.Major
        Minor = $version.Minor
        Build = $version.Build
        DisplayVersion = $displayVersion
        Caption = $os.Caption
    }
}

function Get-SystemInfo {
    <#
    .SYNOPSIS
        Gets system information for debugging.
    .OUTPUTS
        Hashtable with system information.
    #>
    $winVer = Get-WindowsVersion

    return @{
        User = $env:USERNAME
        ComputerName = $env:COMPUTERNAME
        OSVersion = $winVer.Caption
        OSBuild = $winVer.Build
        DisplayVersion = $winVer.DisplayVersion
        Architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        ProcessorCount = [Environment]::ProcessorCount
        IsAdmin = Test-IsAdmin
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    }
}

# ============================================================================
# Temp File Management
# ============================================================================
$script:MOLE_TEMP_FILES = [System.Collections.ArrayList]::new()

function New-MoleTempFile {
    <#
    .SYNOPSIS
        Creates a tracked temporary file.
    .OUTPUTS
        Path to the temporary file.
    #>
    param(
        [string]$Prefix = "mole"
    )

    $tempPath = [System.IO.Path]::GetTempFileName()
    $newPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetDirectoryName($tempPath),
        "$Prefix-$([System.IO.Path]::GetFileName($tempPath))"
    )

    Move-Item $tempPath $newPath -Force
    $script:MOLE_TEMP_FILES.Add($newPath) | Out-Null

    return $newPath
}

function Remove-MoleTempFiles {
    <#
    .SYNOPSIS
        Cleans up all tracked temporary files.
    #>
    foreach ($file in $script:MOLE_TEMP_FILES) {
        if (Test-Path $file) {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }
    $script:MOLE_TEMP_FILES.Clear()
}

# ============================================================================
# Section Tracking (for progress indication)
# ============================================================================
$script:TRACK_SECTION = $false
$script:SECTION_ACTIVITY = $false

function Start-MoleSection {
    <#
    .SYNOPSIS
        Starts a new UI section.
    .PARAMETER Title
        The section title to display.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $script:TRACK_SECTION = $true
    $script:SECTION_ACTIVITY = $false

    Write-Host ""
    Write-Host "$($script:PURPLE_BOLD)$($script:ICON_ARROW) $Title$($script:NC)"
}

function Stop-MoleSection {
    <#
    .SYNOPSIS
        Ends the current section, showing "Nothing to tidy" if no activity.
    #>
    if ($script:TRACK_SECTION -and -not $script:SECTION_ACTIVITY) {
        Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) Nothing to tidy"
    }
    $script:TRACK_SECTION = $false
}

function Set-MoleActivity {
    <#
    .SYNOPSIS
        Marks activity in the current section.
    #>
    if ($script:TRACK_SECTION) {
        $script:SECTION_ACTIVITY = $true
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Get-MoleConfigDir'
    'Ensure-MoleConfigDir'
    'Get-FreeSpace'
    'Format-ByteSize'
    'Get-PathSize'
    'Test-IsAdmin'
    'Test-IsInteractive'
    'Get-OptimalParallelJobs'
    'Get-WindowsVersion'
    'Get-SystemInfo'
    'New-MoleTempFile'
    'Remove-MoleTempFiles'
    'Start-MoleSection'
    'Stop-MoleSection'
    'Set-MoleActivity'
) -Variable @(
    'ESC', 'GREEN', 'BLUE', 'CYAN', 'YELLOW', 'PURPLE', 'PURPLE_BOLD', 'RED', 'GRAY', 'NC',
    'ICON_CONFIRM', 'ICON_ADMIN', 'ICON_SUCCESS', 'ICON_ERROR', 'ICON_WARNING',
    'ICON_EMPTY', 'ICON_SOLID', 'ICON_LIST', 'ICON_ARROW', 'ICON_DRY_RUN',
    'ICON_NAV_UP', 'ICON_NAV_DOWN',
    'MOLE_TEMP_FILE_AGE_DAYS', 'MOLE_ORPHAN_AGE_DAYS', 'MOLE_LOG_AGE_DAYS',
    'MOLE_CRASH_REPORT_AGE_DAYS', 'MOLE_SAVED_STATE_AGE_DAYS',
    'MOLE_CONFIG_DIR', 'MOLE_LOG_FILE', 'MOLE_DEBUG_LOG_FILE', 'MOLE_WHITELIST_FILE',
    'DEFAULT_WHITELIST_PATTERNS'
)
