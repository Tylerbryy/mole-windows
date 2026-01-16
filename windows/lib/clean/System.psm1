# Mole Windows - System Cleanup Module
# Orchestrates system-level cleanup with admin privilege handling

#Requires -Version 5.1

# Import dependencies
$coreModules = @(
    (Join-Path $PSScriptRoot "..\core\Base.psm1"),
    (Join-Path $PSScriptRoot "..\core\Log.psm1"),
    (Join-Path $PSScriptRoot "..\core\FileOps.psm1"),
    (Join-Path $PSScriptRoot "..\core\Elevation.psm1"),
    (Join-Path $PSScriptRoot "..\core\UI.psm1")
)

$cleanModules = @(
    (Join-Path $PSScriptRoot "User.psm1"),
    (Join-Path $PSScriptRoot "Browsers.psm1"),
    (Join-Path $PSScriptRoot "Dev.psm1"),
    (Join-Path $PSScriptRoot "Windows.psm1")
)

foreach ($module in $coreModules + $cleanModules) {
    Import-Module $module -Force -DisableNameChecking -ErrorAction SilentlyContinue
}

# Prevent multiple loading
if ($script:MOLE_CLEAN_SYSTEM_LOADED) { return }
$script:MOLE_CLEAN_SYSTEM_LOADED = $true

# ============================================================================
# System Information
# ============================================================================

function Get-CleanupTargets {
    <#
    .SYNOPSIS
        Gets a list of all cleanup targets with their estimated sizes.
    .OUTPUTS
        Array of hashtables with Name, Path, Size, RequiresAdmin properties.
    #>
    $targets = @()

    # User temp
    $tempPath = $env:TEMP
    if (Test-Path $tempPath) {
        $targets += @{
            Name = "User Temp Files"
            Path = $tempPath
            Size = Get-PathSize -Path $tempPath
            RequiresAdmin = $false
            Category = "User"
        }
    }

    # Browser caches
    $browsers = Get-InstalledBrowsers
    foreach ($browser in $browsers) {
        $browserSize = 0
        foreach ($cachePath in $browser.CachePaths) {
            $fullPath = Join-Path $browser.DataPath $cachePath
            if (Test-Path $fullPath -ErrorAction SilentlyContinue) {
                $browserSize += Get-PathSize -Path $fullPath
            }
        }

        if ($browserSize -gt 0) {
            $targets += @{
                Name = "$($browser.Name) Cache"
                Path = $browser.DataPath
                Size = $browserSize
                RequiresAdmin = $false
                Category = "Browser"
            }
        }
    }

    # Windows Update
    $wuPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
    if (Test-Path $wuPath) {
        $targets += @{
            Name = "Windows Update Cache"
            Path = $wuPath
            Size = Get-PathSize -Path $wuPath
            RequiresAdmin = $true
            Category = "Windows"
        }
    }

    # System temp
    $systemTemp = Join-Path $env:SystemRoot "Temp"
    if (Test-Path $systemTemp) {
        $targets += @{
            Name = "System Temp Files"
            Path = $systemTemp
            Size = Get-PathSize -Path $systemTemp
            RequiresAdmin = $true
            Category = "Windows"
        }
    }

    # Recycle Bin (estimate)
    try {
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.Namespace(10)
        $items = $recycleBin.Items()
        $binSize = 0
        foreach ($item in $items) {
            try { $binSize += $item.Size } catch { }
        }
        if ($binSize -gt 0) {
            $targets += @{
                Name = "Recycle Bin"
                Path = "shell:RecycleBinFolder"
                Size = $binSize
                RequiresAdmin = $false
                Category = "User"
            }
        }
    }
    catch { }

    return $targets | Sort-Object -Property Size -Descending
}

function Show-CleanupSummary {
    <#
    .SYNOPSIS
        Displays a summary of items that can be cleaned.
    #>
    $targets = Get-CleanupTargets

    Write-MoleBanner

    Write-Host ""
    Write-Host "$($script:PURPLE_BOLD)Cleanup Targets$($script:NC)"
    Write-MoleDivider -Char '-' -Width 60

    $totalSize = 0
    $adminSize = 0

    foreach ($target in $targets) {
        if ($target.Size -gt 0) {
            $sizeStr = Format-ByteSize -Bytes $target.Size
            $adminMarker = if ($target.RequiresAdmin) { " $($script:GRAY)(admin)$($script:NC)" } else { "" }

            Write-Host "  $($script:ICON_LIST) $($target.Name): $($script:GREEN)$sizeStr$($script:NC)$adminMarker"

            $totalSize += $target.Size
            if ($target.RequiresAdmin) {
                $adminSize += $target.Size
            }
        }
    }

    Write-MoleDivider -Char '-' -Width 60
    Write-Host "  Total: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"

    if ($adminSize -gt 0 -and -not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)($([int]($adminSize / 1MB)) MB requires admin)$($script:NC)"
    }

    Write-Host ""
}

# ============================================================================
# Full System Cleanup
# ============================================================================

function Invoke-FullCleanup {
    <#
    .SYNOPSIS
        Performs a full system cleanup.
    .PARAMETER DryRun
        Preview what would be cleaned without actually deleting.
    .PARAMETER IncludeBrowsers
        Include browser cache cleanup (default: true).
    .PARAMETER IncludeDevTools
        Include developer tools cleanup (default: true).
    .PARAMETER IncludeRecycleBin
        Include Recycle Bin cleanup (default: true).
    .PARAMETER SkipConfirmation
        Skip the confirmation prompt.
    .PARAMETER Drive
        Drive letter to show free space for (default: C).
    .OUTPUTS
        Hashtable with CleanedSize and CleanedCount.
    #>
    param(
        [switch]$DryRun,

        [bool]$IncludeBrowsers = $true,
        [bool]$IncludeDevTools = $true,
        [bool]$IncludeRecycleBin = $true,

        [switch]$SkipConfirmation,

        [string]$Drive = "C"
    )

    # Set dry-run mode
    Set-MoleDryRun -Enabled $DryRun

    # Show banner
    Write-MoleBanner

    if ($DryRun) {
        Write-Host "$($script:YELLOW)DRY RUN MODE - No files will be deleted$($script:NC)"
        Write-Host ""
    }

    # Show current disk space
    $freeSpace = Get-FreeSpace -DriveLetter $Drive
    Write-Host "Free disk space ($($Drive):): $($script:CYAN)$freeSpace$($script:NC)"
    Write-Host ""

    # Confirmation (unless skipped)
    if (-not $SkipConfirmation -and -not $DryRun) {
        $confirm = Read-MoleConfirmation -Message "Proceed with cleanup?" -Default $true
        if (-not $confirm) {
            Write-Host "Cleanup cancelled."
            return @{ CleanedSize = 0; Cancelled = $true }
        }
    }

    $startTime = Get-Date
    [long]$totalSize = 0

    # Helper function to safely extract CleanedSize from function results
    # (handles PowerShell's behavior of returning arrays when functions output content)
    function Get-SafeCleanedSize($result) {
        if ($null -eq $result) { return 0 }
        if ($result -is [array]) {
            # Find the hashtable in the array
            foreach ($item in $result) {
                if ($item -is [hashtable] -and $item.ContainsKey('CleanedSize')) {
                    return [long]$item.CleanedSize
                }
            }
            return 0
        }
        if ($result -is [hashtable] -and $result.ContainsKey('CleanedSize')) {
            return [long]$result.CleanedSize
        }
        return 0
    }

    # User cleanup
    $result = Invoke-UserCleanup -IncludeRecycleBin $IncludeRecycleBin
    $totalSize += Get-SafeCleanedSize $result

    # Browser cleanup
    if ($IncludeBrowsers) {
        $result = Invoke-BrowserCleanup
        $totalSize += Get-SafeCleanedSize $result
    }

    # Developer tools cleanup
    if ($IncludeDevTools) {
        Invoke-DevCleanup | Out-Null
    }

    # Windows-specific cleanup
    $result = Invoke-WindowsCleanup
    $totalSize += Get-SafeCleanedSize $result

    # Summary
    $endTime = Get-Date
    $duration = $endTime - $startTime

    # Get new free space
    $newFreeSpace = Get-FreeSpace -DriveLetter $Drive

    Write-Host ""
    Write-MoleDivider

    if ($DryRun) {
        Write-Host "$($script:BLUE)DRY RUN COMPLETE$($script:NC)"
        Write-Host "Would free approximately: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"
    }
    else {
        Write-Host "$($script:BLUE)CLEANUP COMPLETE$($script:NC)"
        Write-Host "Free space ($($Drive):): $($script:CYAN)$freeSpace$($script:NC) -> $($script:GREEN)$newFreeSpace$($script:NC)"
    }

    Write-MoleDivider

    return @{
        CleanedSize = $totalSize
        Duration = $duration
    }
}

# ============================================================================
# Quick Cleanup (Essential Only)
# ============================================================================

function Invoke-QuickCleanup {
    <#
    .SYNOPSIS
        Performs a quick cleanup of essential items only.
    .DESCRIPTION
        Cleans temp files, browser cache, and Recycle Bin.
    .PARAMETER DryRun
        Preview what would be cleaned.
    .PARAMETER Drive
        Drive letter (not used in quick cleanup, for API consistency).
    #>
    param(
        [switch]$DryRun,
        [string]$Drive = "C"
    )

    Set-MoleDryRun -Enabled $DryRun

    Write-MoleBanner

    if ($DryRun) {
        Write-Host "$($script:YELLOW)DRY RUN MODE$($script:NC)"
    }

    Write-Host "$($script:PURPLE_BOLD)Quick Cleanup$($script:NC)"
    Write-Host ""

    $totalSize = 0

    # User temp only
    $result = Clear-UserTempFiles
    $totalSize += $result.CleanedSize

    # Browser caches
    $result = Invoke-BrowserCleanup -WarnIfRunning $false
    $totalSize += $result.CleanedSize

    # Recycle Bin
    $result = Clear-MoleRecycleBin
    $totalSize += $result.CleanedSize

    Write-Host ""
    Write-MoleDivider -Char '-' -Width 40

    if ($DryRun) {
        Write-Host "Would free: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"
    }
    else {
        Write-Host "Cleaned: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"
    }

    return @{ CleanedSize = $totalSize }
}

# ============================================================================
# Selective Cleanup
# ============================================================================

function Invoke-SelectiveCleanup {
    <#
    .SYNOPSIS
        Allows user to select which items to clean.
    .PARAMETER DryRun
        Preview what would be cleaned.
    .PARAMETER Drive
        Drive letter (not used in selective cleanup, for API consistency).
    #>
    param(
        [switch]$DryRun,
        [string]$Drive = "C"
    )

    Set-MoleDryRun -Enabled $DryRun

    Write-MoleBanner

    # Get cleanup targets
    $targets = Get-CleanupTargets | Where-Object { $_.Size -gt 0 }

    if ($targets.Count -eq 0) {
        Write-Host "No cleanup targets found."
        return @{ CleanedSize = 0 }
    }

    # Build options list
    $options = $targets | ForEach-Object {
        "$($_.Name) ($(Format-ByteSize -Bytes $_.Size))"
    }

    # Multi-select
    $selected = Read-MoleMultiSelect -Message "Select items to clean:" -Options $options

    if ($selected.Count -eq 0) {
        Write-Host "No items selected."
        return @{ CleanedSize = 0 }
    }

    $totalSize = 0

    foreach ($idx in $selected) {
        $target = $targets[$idx]

        if ($target.RequiresAdmin -and -not (Test-IsElevated)) {
            Write-MoleWarning "Skipping $($target.Name) - requires admin"
            continue
        }

        # Clean based on category
        switch ($target.Category) {
            "User" {
                if ($target.Name -eq "Recycle Bin") {
                    $result = Clear-MoleRecycleBin
                    $totalSize += $result.CleanedSize
                }
                elseif ($target.Name -eq "User Temp Files") {
                    $result = Clear-UserTempFiles
                    $totalSize += $result.CleanedSize
                }
            }
            "Browser" {
                # Find and clean specific browser
                $browserName = $target.Name -replace " Cache$", ""
                switch -Wildcard ($browserName) {
                    "*Chrome*" { $result = Clear-ChromeCache; $totalSize += $result.CleanedSize }
                    "*Edge*" { $result = Clear-EdgeCache; $totalSize += $result.CleanedSize }
                    "*Firefox*" { $result = Clear-FirefoxCache; $totalSize += $result.CleanedSize }
                    "*Brave*" { $result = Clear-BraveCache; $totalSize += $result.CleanedSize }
                }
            }
            "Windows" {
                if ($target.Name -eq "Windows Update Cache") {
                    $result = Clear-WindowsUpdateCache
                    $totalSize += $result.CleanedSize
                }
                elseif ($target.Name -eq "System Temp Files") {
                    $result = Clear-SystemTemp
                    $totalSize += $result.CleanedSize
                }
            }
        }
    }

    Write-Host ""
    Write-MoleDivider -Char '-' -Width 40

    if ($DryRun) {
        Write-Host "Would free: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"
    }
    else {
        Write-Host "Cleaned: $($script:GREEN)$(Format-ByteSize -Bytes $totalSize)$($script:NC)"
    }

    return @{ CleanedSize = $totalSize }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Get-CleanupTargets'
    'Show-CleanupSummary'
    'Invoke-FullCleanup'
    'Invoke-QuickCleanup'
    'Invoke-SelectiveCleanup'
)
