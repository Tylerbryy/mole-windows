#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Mole - Windows System Cleaner
.DESCRIPTION
    A safe and thorough system cleaner for Windows.
    Cleans temp files, browser caches, developer tool caches, and more.
.PARAMETER Command
    The command to run: clean, analyze, status, whitelist, purge, optimize, help, version
.PARAMETER DryRun
    Preview what would be cleaned without deleting anything.
.PARAMETER Quick
    Quick cleanup mode - only essential items.
.PARAMETER Select
    Interactive selection of items to clean.
.PARAMETER Admin
    Request admin privileges for full cleanup.
.PARAMETER DebugMode
    Enable debug logging.
.EXAMPLE
    .\mole.ps1 clean
    Performs a full system cleanup.
.EXAMPLE
    .\mole.ps1 clean --dry-run
    Preview cleanup without deleting files.
.EXAMPLE
    .\mole.ps1 clean --quick
    Quick cleanup of essential items only.
.EXAMPLE
    .\mole.ps1 whitelist
    Open the whitelist manager.
.NOTES
    Author: Mole Project
    License: MIT
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("clean", "analyze", "status", "whitelist", "purge", "optimize", "help", "version", "")]
    [string]$Command = "",

    [Alias("n")]
    [switch]$DryRun,

    [Alias("q")]
    [switch]$Quick,

    [Alias("s")]
    [switch]$Select,

    [switch]$Admin,

    [Alias("d")]
    [switch]$DebugMode,

    [switch]$Yes,

    [switch]$NoBrowser,

    [switch]$NoDev,

    [switch]$NoRecycleBin,

    [ValidatePattern("^[A-Za-z]$")]
    [string]$Drive = "C",

    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingArgs
)

# Script root
$script:MOLE_ROOT = $PSScriptRoot

# Set debug mode
if ($DebugMode) {
    $env:MOLE_DEBUG = "1"
}

# Import modules
$modulePaths = @(
    (Join-Path $MOLE_ROOT "lib\core\Base.psm1"),
    (Join-Path $MOLE_ROOT "lib\core\Log.psm1"),
    (Join-Path $MOLE_ROOT "lib\core\FileOps.psm1"),
    (Join-Path $MOLE_ROOT "lib\core\PathProtection.psm1"),
    (Join-Path $MOLE_ROOT "lib\core\Elevation.psm1"),
    (Join-Path $MOLE_ROOT "lib\core\UI.psm1"),
    (Join-Path $MOLE_ROOT "lib\clean\User.psm1"),
    (Join-Path $MOLE_ROOT "lib\clean\Browsers.psm1"),
    (Join-Path $MOLE_ROOT "lib\clean\Dev.psm1"),
    (Join-Path $MOLE_ROOT "lib\clean\Windows.psm1"),
    (Join-Path $MOLE_ROOT "lib\clean\System.psm1"),
    (Join-Path $MOLE_ROOT "lib\manage\Whitelist.psm1")
)

foreach ($modulePath in $modulePaths) {
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -DisableNameChecking -Scope Global -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Color Constants (for script scope access)
# ============================================================================
$script:ESC = [char]27
$script:GREEN = "$($script:ESC)[0;32m"
$script:BLUE = "$($script:ESC)[0;34m"
$script:CYAN = "$($script:ESC)[0;36m"
$script:YELLOW = "$($script:ESC)[0;33m"
$script:PURPLE = "$($script:ESC)[0;35m"
$script:PURPLE_BOLD = "$($script:ESC)[1;35m"
$script:GRAY = "$($script:ESC)[0;90m"
$script:NC = "$($script:ESC)[0m"
$script:ICON_SUCCESS = [char]0x2713
$script:ICON_ERROR = [char]0x263B
$script:ICON_ARROW = [char]0x27A4
$script:ICON_LIST = [char]0x2022

# ============================================================================
# Helper Functions (for script scope)
# ============================================================================
function Write-MoleBanner {
    $banner = @"
$($script:PURPLE_BOLD)
    __  ___      __
   /  |/  /___  / /__
  / /|_/ / __ \/ / _ \
 / /  / / /_/ / /  __/
/_/  /_/\____/_/\___/
$($script:NC)
"@
    Write-Host $banner
    Write-Host "$($script:GRAY)Windows System Cleaner$($script:NC)"
}

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2}GB" -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { return "{0:N1}MB" -f ($Bytes / 1MB) }
    elseif ($Bytes -ge 1KB) { return "{0:N0}KB" -f ($Bytes / 1KB) }
    else { return "{0}B" -f $Bytes }
}

function Get-DirSize([string]$Path) {
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [long]$(if ($null -eq $size) { 0 } else { $size })
    }
    catch { return 0 }
}

# ============================================================================
# Version Information
# ============================================================================
$script:MOLE_VERSION = "1.0.0-windows"

function Show-Version {
    Write-Host "Mole $script:MOLE_VERSION"
    Write-Host "Windows System Cleaner"
    Write-Host ""
    Write-Host "PowerShell $($PSVersionTable.PSVersion)"

    # Get Windows version info directly (avoiding module scope issues)
    $version = [System.Environment]::OSVersion.Version
    $displayVersion = try {
        (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion -ErrorAction Stop).DisplayVersion
    } catch { "Unknown" }
    Write-Host "Windows $displayVersion (Build $($version.Build))"
}

# ============================================================================
# Help
# ============================================================================
function Show-Help {
    $banner = @"
$($script:PURPLE_BOLD)
    __  ___      __
   /  |/  /___  / /__
  / /|_/ / __ \/ / _ \
 / /  / / /_/ / /  __/
/_/  /_/\____/_/\___/
$($script:NC)
Mole - Windows System Cleaner
Version $script:MOLE_VERSION

USAGE:
    mole <command> [options]

COMMANDS:
    clean           Clean system caches and temp files
    analyze         Analyze disk usage (requires Go TUI)
    status          Show system status (requires Go TUI)
    whitelist       Manage protected paths
    purge           Clean project build artifacts
    optimize        Optimize system (cache rebuild, service refresh)
    help            Show this help message
    version         Show version information

CLEAN OPTIONS:
    -DryRun, -n     Preview what would be cleaned
    -Quick, -q      Quick cleanup (temp, browser, recycle bin only)
    -Select, -s     Interactive selection of items to clean
    -Admin          Request admin privileges for full cleanup
    -Yes            Skip confirmation prompts
    -NoBrowser      Skip browser cache cleanup
    -NoDev          Skip developer tools cleanup
    -NoRecycleBin   Skip Recycle Bin cleanup
    -Drive X        Show free space for drive X (default: C)

GLOBAL OPTIONS:
    -DebugMode, -d  Enable debug logging

EXAMPLES:
    mole clean                  Full cleanup with confirmation
    mole clean -n               Preview without deleting (dry-run)
    mole clean -q               Quick essential cleanup
    mole clean -Admin           Full cleanup with admin rights
    mole clean -Drive C         Show C: drive free space
    mole whitelist              Manage whitelist interactively

CONFIGURATION:
    Config directory: $env:LOCALAPPDATA\mole
    Whitelist file:   $env:LOCALAPPDATA\mole\whitelist
    Log file:         $env:LOCALAPPDATA\mole\mole.log

"@
    Write-Host $banner
}

# ============================================================================
# Clean Command
# ============================================================================
function Invoke-CleanCommand {
    # Initialize whitelist
    Initialize-Whitelist

    # Handle admin elevation
    if ($Admin -and -not (Test-IsElevated)) {
        Write-MoleInfo "Requesting administrator privileges..."

        $scriptPath = $MyInvocation.PSCommandPath
        if (-not $scriptPath) {
            $scriptPath = $PSCommandPath
        }

        $argList = @("clean")
        if ($DryRun) { $argList += "-DryRun" }
        if ($Quick) { $argList += "-Quick" }
        if ($Yes) { $argList += "-Yes" }
        if ($NoBrowser) { $argList += "-NoBrowser" }
        if ($NoDev) { $argList += "-NoDev" }
        if ($NoRecycleBin) { $argList += "-NoRecycleBin" }
        if ($DebugMode) { $argList += "-DebugMode" }
        if ($Drive) { $argList += "-Drive"; $argList += $Drive }

        try {
            Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"", $argList `
                -Verb RunAs `
                -Wait
        }
        catch {
            Write-MoleWarning "Administrator access was declined or failed"
        }

        return
    }

    # Run appropriate cleanup (suppress return value output)
    if ($Quick) {
        Invoke-QuickCleanup -DryRun:$DryRun -Drive $Drive | Out-Null
    }
    elseif ($Select) {
        Invoke-SelectiveCleanup -DryRun:$DryRun -Drive $Drive | Out-Null
    }
    else {
        Invoke-FullCleanup `
            -DryRun:$DryRun `
            -IncludeBrowsers:(-not $NoBrowser) `
            -IncludeDevTools:(-not $NoDev) `
            -IncludeRecycleBin:(-not $NoRecycleBin) `
            -SkipConfirmation:$Yes `
            -Drive $Drive | Out-Null
    }
}

# ============================================================================
# Whitelist Command
# ============================================================================
function Invoke-WhitelistCommand {
    $subCommand = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { "" }

    switch ($subCommand) {
        "show" {
            Show-Whitelist
        }
        "reset" {
            Reset-Whitelist
        }
        "add" {
            if ($RemainingArgs.Count -gt 1) {
                Add-WhitelistPattern -Pattern $RemainingArgs[1]
            }
            else {
                Write-MoleError "Usage: mole whitelist add <pattern>"
            }
        }
        "remove" {
            if ($RemainingArgs.Count -gt 1) {
                Remove-WhitelistPattern -Pattern $RemainingArgs[1]
            }
            else {
                Write-MoleError "Usage: mole whitelist remove <pattern>"
            }
        }
        default {
            Show-WhitelistManager
        }
    }
}

# ============================================================================
# Analyze Command
# ============================================================================
function Invoke-AnalyzeCommand {
    # Check for Go binary
    $analyzeExe = Join-Path $MOLE_ROOT "bin\analyze.exe"

    if (Test-Path $analyzeExe) {
        & $analyzeExe $RemainingArgs
    }
    else {
        Write-Host "Disk analyzer not found." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Run these commands to build the analyzer:"
        Write-Host "  cd $(Split-Path $MOLE_ROOT -Parent)" -ForegroundColor DarkGray
        Write-Host "  `$env:GOOS='windows'; `$env:GOARCH='amd64'" -ForegroundColor DarkGray
        Write-Host "  go build -o windows/bin/analyze.exe ./cmd/analyze" -ForegroundColor DarkGray
        Write-Host ""

        # Fallback to simple disk info
        Write-Host "Current disk space:"
        Get-PSDrive -PSProvider FileSystem |
            Where-Object { $_.Used -gt 0 } |
            ForEach-Object {
                $total = $_.Used + $_.Free
                $usedPct = if ($total -gt 0) { [int](($_.Used / $total) * 100) } else { 0 }
                [PSCustomObject]@{
                    Drive = $_.Name
                    Used = "{0:N2} GB" -f ($_.Used / 1GB)
                    Free = "{0:N2} GB" -f ($_.Free / 1GB)
                    Total = "{0:N2} GB" -f ($total / 1GB)
                    "Used%" = "$usedPct%"
                }
            } | Format-Table -AutoSize
    }
}

# ============================================================================
# Status Command
# ============================================================================
function Invoke-StatusCommand {
    # Check for Go binary
    $statusExe = Join-Path $MOLE_ROOT "bin\status.exe"

    if (Test-Path $statusExe) {
        & $statusExe $RemainingArgs
    }
    else {
        Write-Host "Status dashboard not found. Showing basic info..." -ForegroundColor Yellow
        Write-Host ""

        # Get system info inline
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $os = Get-CimInstance Win32_OperatingSystem
        $displayVersion = try {
            (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion -ErrorAction Stop).DisplayVersion
        } catch { "Unknown" }

        Write-Host "System Status" -ForegroundColor Magenta
        Write-Host ("-" * 50) -ForegroundColor DarkGray

        Write-Host ("  {0,-15} {1}" -f "Computer:", $env:COMPUTERNAME)
        Write-Host ("  {0,-15} {1}" -f "User:", $env:USERNAME)
        Write-Host ("  {0,-15} {1}" -f "OS:", "$($os.Caption) ($displayVersion)")
        Write-Host ("  {0,-15} {1}" -f "Architecture:", $(if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }))
        Write-Host ("  {0,-15} {1}" -f "Processors:", [Environment]::ProcessorCount)
        Write-Host ("  {0,-15} {1}" -f "Admin:", $(if ($isAdmin) { "Yes" } else { "No" }))

        Write-Host ""
        Write-Host "Disk Space" -ForegroundColor Magenta
        Write-Host ("-" * 50) -ForegroundColor DarkGray

        Get-PSDrive -PSProvider FileSystem |
            Where-Object { $_.Used -gt 0 } |
            ForEach-Object {
                $total = $_.Used + $_.Free
                $usedPct = if ($total -gt 0) { [int](($_.Used / $total) * 100) } else { 0 }
                $freeGB = "{0:N2} GB" -f ($_.Free / 1GB)
                $totalGB = "{0:N2} GB" -f ($total / 1GB)
                Write-Host ("  {0,-15} {1} free of {2} ({3}% used)" -f "Drive $($_.Name):", $freeGB, $totalGB, $usedPct)
            }

        Write-Host ""
        Write-Host "Run 'mole clean --dry-run' to see cleanup opportunities" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Purge Command
# ============================================================================
function Invoke-PurgeCommand {
    Write-MoleBanner

    Write-Host "$($script:PURPLE_BOLD)Project Artifact Cleanup$($script:NC)"
    Write-Host "$($script:GRAY)Cleans build artifacts from project directories$($script:NC)"
    Write-Host ""

    $targetDir = if ($RemainingArgs.Count -gt 0) { $RemainingArgs[0] } else { Get-Location }

    if (-not (Test-Path $targetDir)) {
        Write-Host "$($script:ICON_ERROR) Directory not found: $targetDir" -ForegroundColor Yellow
        return
    }

    Write-Host "Scanning: $targetDir"
    Write-Host ""

    # Common build artifact directories
    $artifactPatterns = @(
        "node_modules",
        ".next",
        ".nuxt",
        "dist",
        "build",
        "target",           # Rust/Java
        "bin\Debug",        # .NET
        "bin\Release",      # .NET
        "obj",              # .NET
        "__pycache__",
        ".pytest_cache",
        ".mypy_cache",
        "*.pyc",
        ".tox",
        ".eggs",
        "*.egg-info",
        ".gradle",
        ".idea",            # JetBrains (optional)
        ".vscode",          # VS Code (optional)
        "coverage",
        ".nyc_output",
        ".parcel-cache",
        ".turbo",
        ".vite"
    )

    $found = @()

    foreach ($pattern in $artifactPatterns) {
        $matches = Get-ChildItem -Path $targetDir -Filter $pattern -Recurse -Directory -ErrorAction SilentlyContinue
        foreach ($match in $matches) {
            $size = Get-DirSize -Path $match.FullName
            if ($size -gt 0) {
                $found += @{
                    Path = $match.FullName
                    Size = $size
                    Name = $match.Name
                }
            }
        }
    }

    if ($found.Count -eq 0) {
        Write-Host "No build artifacts found."
        return
    }

    $totalSize = ($found | Measure-Object -Property Size -Sum).Sum

    Write-Host "Found $($found.Count) artifact directories ($(Format-Size $totalSize)):"
    Write-Host ""

    foreach ($item in ($found | Sort-Object Size -Descending | Select-Object -First 20)) {
        $relativePath = $item.Path.Replace($targetDir, ".")
        Write-Host "  $($script:ICON_LIST) $relativePath ($($script:GREEN)$(Format-Size $item.Size)$($script:NC))"
    }

    if ($found.Count -gt 20) {
        Write-Host "  $($script:GRAY)... and $($found.Count - 20) more$($script:NC)"
    }

    Write-Host ""

    if ($DryRun) {
        Write-Host "$($script:YELLOW)DRY RUN: Would remove $(Format-Size $totalSize)$($script:NC)"
        return
    }

    # Simple confirmation prompt
    $response = Read-Host "Remove these directories? [y/N]"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Cancelled."
        return
    }

    $cleaned = 0
    foreach ($item in $found) {
        try {
            Remove-Item -Path $item.Path -Recurse -Force -ErrorAction Stop
            $cleaned++
        }
        catch { }
    }

    Write-Host ""
    Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) Removed $cleaned directories ($(Format-Size $totalSize))"
}

# ============================================================================
# Optimize Command
# ============================================================================
function Invoke-OptimizeCommand {
    Write-MoleBanner

    Write-Host "$($script:PURPLE_BOLD)System Optimization$($script:NC)"
    Write-Host "$($script:GRAY)Rebuilds caches and refreshes services$($script:NC)"
    Write-Host ""

    # Check for admin
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # DNS cache flush
    Write-Host "$($script:ICON_ARROW) Flushing DNS cache..."
    if (-not $DryRun) {
        ipconfig /flushdns | Out-Null
        Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) DNS cache flushed"
    }
    else {
        Write-Host "  $($script:YELLOW)->$($script:NC) Would flush DNS cache"
    }

    # Icon cache rebuild (if requested)
    if ($Admin -or $isAdmin) {
        Write-Host "$($script:ICON_ARROW) Rebuilding icon cache..."

        # Stop Explorer
        if (-not $DryRun) {
            $explorerProc = Get-Process -Name explorer -ErrorAction SilentlyContinue
            if ($explorerProc) {
                # Kill explorer and let it restart
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                # Delete icon cache
                $iconCachePath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*.db"
                Remove-Item -Path $iconCachePath -Force -ErrorAction SilentlyContinue

                # Explorer will restart automatically
                Start-Sleep -Seconds 2

                Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) Icon cache rebuilt"
            }
        }
        else {
            Write-Host "  $($script:YELLOW)->$($script:NC) Would rebuild icon cache"
        }
    }

    # Windows Store cache reset
    Write-Host "$($script:ICON_ARROW) Resetting Windows Store cache..."
    if (-not $DryRun) {
        $wsPath = Join-Path $env:LOCALAPPDATA "Packages\*Store*\LocalCache"
        $stores = Get-ChildItem -Path $wsPath -ErrorAction SilentlyContinue
        foreach ($store in $stores) {
            Remove-Item -Path "$($store.FullName)\*" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) Windows Store cache reset"
    }
    else {
        Write-Host "  $($script:YELLOW)->$($script:NC) Would reset Windows Store cache"
    }

    Write-Host ""
    Write-Host ("-" * 50) -ForegroundColor DarkGray
    Write-Host "Optimization complete"
}

# ============================================================================
# Main Entry Point
# ============================================================================
function Main {
    # Handle no command
    if ([string]::IsNullOrWhiteSpace($Command)) {
        Show-Help
        return
    }

    switch ($Command) {
        "clean" {
            Invoke-CleanCommand
        }
        "analyze" {
            Invoke-AnalyzeCommand
        }
        "status" {
            Invoke-StatusCommand
        }
        "whitelist" {
            Invoke-WhitelistCommand
        }
        "purge" {
            Invoke-PurgeCommand
        }
        "optimize" {
            Invoke-OptimizeCommand
        }
        "help" {
            Show-Help
        }
        "version" {
            Show-Version
        }
        default {
            Write-MoleError "Unknown command: $Command"
            Write-Host "Run 'mole help' for usage information."
        }
    }
}

# Run
Main
