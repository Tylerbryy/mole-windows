# Mole Windows - User Data Cleanup Module
# Cleans user-level temp files, caches, and other cleanable data

#Requires -Version 5.1

# Import dependencies
$coreModules = @(
    (Join-Path $PSScriptRoot "..\core\Base.psm1"),
    (Join-Path $PSScriptRoot "..\core\Log.psm1"),
    (Join-Path $PSScriptRoot "..\core\FileOps.psm1"),
    (Join-Path $PSScriptRoot "..\core\UI.psm1")
)

foreach ($module in $coreModules) {
    Import-Module $module -Force -DisableNameChecking -ErrorAction SilentlyContinue
}

# Prevent multiple loading
if ($script:MOLE_CLEAN_USER_LOADED) { return }
$script:MOLE_CLEAN_USER_LOADED = $true

# ============================================================================
# User Temp Files Cleanup
# ============================================================================

function Clear-UserTempFiles {
    <#
    .SYNOPSIS
        Cleans user temporary files.
    .DESCRIPTION
        Removes old files from the user's temp directories.
    .PARAMETER AgeDays
        Minimum age in days for files to be removed (default: 7).
    .OUTPUTS
        Hashtable with CleanedSize and CleanedCount.
    #>
    param(
        [int]$AgeDays = 7
    )

    Start-MoleSection -Title "User Temp Files"

    $results = @{
        CleanedSize = 0
        CleanedCount = 0
    }

    # User temp directory (%TEMP%)
    $tempPath = $env:TEMP
    if (Test-Path $tempPath) {
        $size = Invoke-SafeClean -Path "$tempPath\*" -Description "User temp files"
        $results.CleanedSize += $size
    }

    # LocalAppData temp (sometimes different from %TEMP%)
    $localTemp = Join-Path $env:LOCALAPPDATA "Temp"
    if ((Test-Path $localTemp) -and $localTemp -ne $tempPath) {
        $size = Invoke-SafeClean -Path "$localTemp\*" -Description "LocalAppData temp"
        $results.CleanedSize += $size
    }

    Stop-MoleSection
    return $results
}

# ============================================================================
# Recycle Bin Cleanup
# ============================================================================

function Clear-MoleRecycleBin {
    <#
    .SYNOPSIS
        Empties the Windows Recycle Bin.
    .OUTPUTS
        Hashtable with CleanedSize.
    #>
    Start-MoleSection -Title "Recycle Bin"

    $results = @{
        CleanedSize = 0
    }

    if (Get-MoleDryRun) {
        # Calculate size of Recycle Bin
        try {
            $shell = New-Object -ComObject Shell.Application
            $recycleBin = $shell.Namespace(10)  # 10 = Recycle Bin
            $items = $recycleBin.Items()

            $totalSize = 0
            foreach ($item in $items) {
                try {
                    if ($item.IsFolder) {
                        # For folders, try to get extended property
                        $size = $recycleBin.GetDetailsOf($item, 2)  # Size column
                        # Parse size string (e.g., "1.5 MB")
                        if ($size -match '([\d.]+)\s*(KB|MB|GB|TB)') {
                            $num = [double]$Matches[1]
                            $unit = $Matches[2]
                            $multiplier = switch ($unit) {
                                "KB" { 1KB }
                                "MB" { 1MB }
                                "GB" { 1GB }
                                "TB" { 1TB }
                                default { 1 }
                            }
                            $totalSize += $num * $multiplier
                        }
                    }
                    else {
                        $totalSize += $item.Size
                    }
                }
                catch { }
            }

            if ($totalSize -gt 0) {
                Set-MoleActivity
                Write-MoleDryRun "Recycle Bin - would clean $(Format-ByteSize -Bytes $totalSize)"
                $results.CleanedSize = $totalSize
            }
        }
        catch {
            Write-MoleDebug "Could not calculate Recycle Bin size: $($_.Exception.Message)"
        }
    }
    else {
        try {
            # Use Microsoft.PowerShell.Management\Clear-RecycleBin cmdlet (available in PS 5.1+)
            Microsoft.PowerShell.Management\Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Set-MoleActivity
            Write-MoleSuccess "Recycle Bin emptied"
        }
        catch {
            Write-MoleDebug "Could not empty Recycle Bin: $($_.Exception.Message)"
        }
    }

    Stop-MoleSection
    return $results
}

# ============================================================================
# Recent Files Cleanup
# ============================================================================

function Clear-RecentFiles {
    <#
    .SYNOPSIS
        Cleans recent files list.
    .DESCRIPTION
        Removes shortcut files from the Recent folder (keeps the feature functional).
    .PARAMETER AgeDays
        Minimum age in days for entries to be removed (default: 30).
    #>
    param(
        [int]$AgeDays = 30
    )

    Start-MoleSection -Title "Recent Files"

    $recentPath = [Environment]::GetFolderPath('Recent')

    if (Test-Path $recentPath) {
        $cutoff = (Get-Date).AddDays(-$AgeDays)
        $oldShortcuts = Get-ChildItem -Path $recentPath -Filter "*.lnk" -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }

        $count = 0
        $size = 0

        foreach ($shortcut in $oldShortcuts) {
            $size += $shortcut.Length
            if (Remove-MolePath -Path $shortcut.FullName -Silent) {
                $count++
            }
        }

        if ($count -gt 0) {
            Set-MoleActivity
            if (Get-MoleDryRun) {
                Write-MoleDryRun "Recent files - would remove $count shortcuts"
            }
            else {
                Write-MoleSuccess "Recent files - removed $count old shortcuts"
            }
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Windows Explorer Caches
# ============================================================================

function Clear-ExplorerCaches {
    <#
    .SYNOPSIS
        Cleans Windows Explorer caches (thumbnails, icon cache).
    #>
    Start-MoleSection -Title "Explorer Caches"

    # Thumbnail cache
    $thumbPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
    if (Test-Path $thumbPath) {
        $thumbDbs = Get-ChildItem -Path $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue

        foreach ($db in $thumbDbs) {
            Invoke-SafeClean -Path $db.FullName -Description "Thumbnail cache ($($db.Name))"
        }

        # Also clean iconcache files
        $iconCache = Get-ChildItem -Path $thumbPath -Filter "iconcache_*.db" -Force -ErrorAction SilentlyContinue
        foreach ($db in $iconCache) {
            Invoke-SafeClean -Path $db.FullName -Description "Icon cache ($($db.Name))"
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Windows Search Index Cache
# ============================================================================

function Clear-SearchCache {
    <#
    .SYNOPSIS
        Cleans Windows Search cache files (not the index itself).
    #>
    Start-MoleSection -Title "Search Cache"

    # User-level search cache
    $searchPath = Join-Path $env:LOCALAPPDATA "Packages\*Search*\LocalState"
    if (Test-Path $searchPath -ErrorAction SilentlyContinue) {
        Invoke-SafeClean -Path "$searchPath\*Cache*" -Description "Search app cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Crash Dumps and Error Reports
# ============================================================================

function Clear-CrashDumps {
    <#
    .SYNOPSIS
        Cleans user-level crash dumps and error reports.
    #>
    Start-MoleSection -Title "Crash Dumps & Error Reports"

    # Windows Error Reports (user level)
    $werPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER"
    if (Test-Path $werPath) {
        Invoke-SafeClean -Path "$werPath\ReportQueue\*" -Description "WER report queue"
        Invoke-SafeClean -Path "$werPath\ReportArchive\*" -Description "WER report archive"
        Invoke-SafeClean -Path "$werPath\Temp\*" -Description "WER temp files"
    }

    # CrashDumps folder
    $crashDumpPath = Join-Path $env:LOCALAPPDATA "CrashDumps"
    if (Test-Path $crashDumpPath) {
        Invoke-SafeClean -Path "$crashDumpPath\*" -Description "User crash dumps"
    }

    # Minidumps in user profile
    $miniDumpPath = Join-Path $env:USERPROFILE "AppData\Local\Temp\*.dmp"
    Invoke-SafeClean -Path $miniDumpPath -Description "Temp dump files"

    Stop-MoleSection
}

# ============================================================================
# Downloaded Installers Cache
# ============================================================================

function Clear-InstallerCache {
    <#
    .SYNOPSIS
        Cleans downloaded installer caches.
    #>
    Start-MoleSection -Title "Installer Caches"

    # Windows Installer cache (user patches)
    $installerPath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\INetCache\IE"
    if (Test-Path $installerPath) {
        Invoke-SafeClean -Path "$installerPath\*" -Description "IE/Edge download cache"
    }

    # Downloaded Program Files
    $downloadedPath = Join-Path $env:SystemRoot "Downloaded Program Files"
    if (Test-Path $downloadedPath) {
        Invoke-SafeClean -Path "$downloadedPath\*" -Description "Downloaded Program Files"
    }

    Stop-MoleSection
}

# ============================================================================
# Clipboard History
# ============================================================================

function Clear-ClipboardHistory {
    <#
    .SYNOPSIS
        Clears the Windows clipboard history.
    #>
    Start-MoleSection -Title "Clipboard History"

    if (Get-MoleDryRun) {
        Set-MoleActivity
        Write-MoleDryRun "Clipboard history - would clear"
    }
    else {
        try {
            # Clear clipboard
            [System.Windows.Forms.Clipboard]::Clear()
            Set-MoleActivity
            Write-MoleSuccess "Clipboard cleared"
        }
        catch {
            # Alternative method using Windows API
            try {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
                [System.Windows.Forms.Clipboard]::Clear()
                Set-MoleActivity
                Write-MoleSuccess "Clipboard cleared"
            }
            catch {
                Write-MoleDebug "Could not clear clipboard: $($_.Exception.Message)"
            }
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Font Cache
# ============================================================================

function Clear-FontCache {
    <#
    .SYNOPSIS
        Cleans the user font cache.
    #>
    Start-MoleSection -Title "Font Cache"

    $fontCachePath = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    if (Test-Path $fontCachePath) {
        # Only clean cache files, not installed fonts
        Invoke-SafeClean -Path "$fontCachePath\*cache*" -Description "Font cache files"
    }

    Stop-MoleSection
}

# ============================================================================
# Master User Cleanup Function
# ============================================================================

function Invoke-UserCleanup {
    <#
    .SYNOPSIS
        Performs all user-level cleanup operations.
    .PARAMETER AgeDays
        Minimum age in days for temp files (default: 7).
    .PARAMETER IncludeRecycleBin
        Include Recycle Bin in cleanup (default: true).
    .OUTPUTS
        Hashtable with total CleanedSize.
    #>
    param(
        [int]$AgeDays = 7,
        [bool]$IncludeRecycleBin = $true
    )

    Write-MoleInfo "Starting user data cleanup..."

    $totalSize = 0

    # Core cleanup
    $result = Clear-UserTempFiles -AgeDays $AgeDays
    $totalSize += $result.CleanedSize

    if ($IncludeRecycleBin) {
        $result = Clear-MoleRecycleBin
        $totalSize += $result.CleanedSize
    }

    # Additional cleanup
    Clear-RecentFiles -AgeDays 30
    Clear-ExplorerCaches
    Clear-SearchCache
    Clear-CrashDumps
    Clear-InstallerCache
    Clear-FontCache

    return @{
        CleanedSize = $totalSize
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Clear-UserTempFiles'
    'Clear-MoleRecycleBin'
    'Clear-RecentFiles'
    'Clear-ExplorerCaches'
    'Clear-SearchCache'
    'Clear-CrashDumps'
    'Clear-InstallerCache'
    'Clear-ClipboardHistory'
    'Clear-FontCache'
    'Invoke-UserCleanup'
)
