# Mole Windows - Windows-Specific Cleanup Module
# Cleans Windows-specific caches: thumbnails, Windows Update, WER, DNS cache, etc.

#Requires -Version 5.1

# Import dependencies
$coreModules = @(
    (Join-Path $PSScriptRoot "..\core\Base.psm1"),
    (Join-Path $PSScriptRoot "..\core\Log.psm1"),
    (Join-Path $PSScriptRoot "..\core\FileOps.psm1"),
    (Join-Path $PSScriptRoot "..\core\Elevation.psm1"),
    (Join-Path $PSScriptRoot "..\core\UI.psm1")
)

foreach ($module in $coreModules) {
    Import-Module $module -Force -DisableNameChecking -ErrorAction SilentlyContinue
}

# Prevent multiple loading
if ($script:MOLE_CLEAN_WINDOWS_LOADED) { return }
$script:MOLE_CLEAN_WINDOWS_LOADED = $true

# ============================================================================
# Windows Update Cache
# ============================================================================

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Cleans Windows Update download cache.
    .DESCRIPTION
        Removes downloaded Windows Update files. Requires admin privileges.
    #>
    Start-MoleSection -Title "Windows Update Cache"

    $wuPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"

    if (-not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)Requires admin - skipping Windows Update cache$($script:NC)"
        Stop-MoleSection
        return @{ CleanedSize = 0; RequiresAdmin = $true }
    }

    if (Test-Path $wuPath) {
        $size = Invoke-SafeClean -Path "$wuPath\*" -Description "Windows Update downloads"
        Stop-MoleSection
        return @{ CleanedSize = $size }
    }

    Stop-MoleSection
    return @{ CleanedSize = 0 }
}

# ============================================================================
# System Temp Files
# ============================================================================

function Clear-SystemTemp {
    <#
    .SYNOPSIS
        Cleans system-level temp files.
    .DESCRIPTION
        Removes old files from C:\Windows\Temp. Requires admin privileges.
    #>
    Start-MoleSection -Title "System Temp Files"

    $systemTemp = Join-Path $env:SystemRoot "Temp"

    if (-not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)Requires admin - skipping system temp$($script:NC)"
        Stop-MoleSection
        return @{ CleanedSize = 0; RequiresAdmin = $true }
    }

    if (Test-Path $systemTemp) {
        # Only clean files older than 7 days to avoid breaking running processes
        $cutoff = (Get-Date).AddDays(-7)
        $items = Get-ChildItem -Path $systemTemp -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }

        $totalSize = 0
        foreach ($item in $items) {
            $size = Get-PathSize -Path $item.FullName
            if (Remove-MolePath -Path $item.FullName -Silent) {
                $totalSize += $size
            }
        }

        if ($totalSize -gt 0) {
            Set-MoleActivity
            if (Get-MoleDryRun) {
                Write-MoleDryRun "System temp - would clean $(Format-ByteSize -Bytes $totalSize)"
            }
            else {
                Write-MoleSuccess "System temp - cleaned $(Format-ByteSize -Bytes $totalSize)"
            }
        }

        Stop-MoleSection
        return @{ CleanedSize = $totalSize }
    }

    Stop-MoleSection
    return @{ CleanedSize = 0 }
}

# ============================================================================
# Windows Error Reports
# ============================================================================

function Clear-WindowsErrorReports {
    <#
    .SYNOPSIS
        Cleans Windows Error Reporting files.
    #>
    Start-MoleSection -Title "Windows Error Reports"

    $totalSize = 0

    # User-level WER
    $userWer = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER"
    if (Test-Path $userWer) {
        $size = Invoke-SafeClean -Path "$userWer\*" -Description "User error reports"
        $totalSize += $size
    }

    # System-level WER (requires admin)
    $systemWer = Join-Path $env:ProgramData "Microsoft\Windows\WER"
    if (Test-Path $systemWer) {
        if (Test-IsElevated) {
            $size = Invoke-SafeClean -Path "$systemWer\ReportQueue\*" -Description "System error report queue"
            $totalSize += $size
            $size = Invoke-SafeClean -Path "$systemWer\ReportArchive\*" -Description "System error report archive"
            $totalSize += $size
        }
        else {
            Write-Host "  $($script:GRAY)System WER requires admin$($script:NC)"
        }
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

# ============================================================================
# DNS Cache
# ============================================================================

function Clear-DnsCache {
    <#
    .SYNOPSIS
        Flushes the Windows DNS resolver cache.
    #>
    Start-MoleSection -Title "DNS Cache"

    if (Get-MoleDryRun) {
        Set-MoleActivity
        Write-MoleDryRun "DNS cache - would flush"
    }
    else {
        try {
            Clear-DnsClientCache -ErrorAction Stop
            Set-MoleActivity
            Write-MoleSuccess "DNS cache flushed"
        }
        catch {
            # Alternative method using ipconfig
            try {
                $null = ipconfig /flushdns 2>$null
                Set-MoleActivity
                Write-MoleSuccess "DNS cache flushed (via ipconfig)"
            }
            catch {
                Write-MoleDebug "Could not flush DNS cache: $($_.Exception.Message)"
            }
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Prefetch Files
# ============================================================================

function Clear-PrefetchFiles {
    <#
    .SYNOPSIS
        Cleans Windows Prefetch files.
    .DESCRIPTION
        Prefetch files help Windows start programs faster, but old ones can be cleaned.
        Requires admin privileges.
    #>
    Start-MoleSection -Title "Prefetch Files"

    $prefetchPath = Join-Path $env:SystemRoot "Prefetch"

    if (-not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)Requires admin - skipping Prefetch cleanup$($script:NC)"
        Stop-MoleSection
        return @{ CleanedSize = 0; RequiresAdmin = $true }
    }

    if (Test-Path $prefetchPath) {
        # Only clean prefetch files older than 14 days
        $cutoff = (Get-Date).AddDays(-14)
        $items = Get-ChildItem -Path $prefetchPath -Filter "*.pf" -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }

        $totalSize = 0
        foreach ($item in $items) {
            $totalSize += $item.Length
            if (-not (Get-MoleDryRun)) {
                Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        if ($totalSize -gt 0) {
            Set-MoleActivity
            if (Get-MoleDryRun) {
                Write-MoleDryRun "Old Prefetch files - would clean $(Format-ByteSize -Bytes $totalSize)"
            }
            else {
                Write-MoleSuccess "Old Prefetch files - cleaned $(Format-ByteSize -Bytes $totalSize)"
            }
        }

        Stop-MoleSection
        return @{ CleanedSize = $totalSize }
    }

    Stop-MoleSection
    return @{ CleanedSize = 0 }
}

# ============================================================================
# Memory Dumps
# ============================================================================

function Clear-MemoryDumps {
    <#
    .SYNOPSIS
        Cleans Windows memory dump files.
    #>
    Start-MoleSection -Title "Memory Dumps"

    $totalSize = 0

    # System memory dumps (requires admin)
    $memoryDmp = Join-Path $env:SystemRoot "MEMORY.DMP"
    if (Test-Path $memoryDmp) {
        if (Test-IsElevated) {
            $size = (Get-Item $memoryDmp).Length
            if (Remove-MolePath -Path $memoryDmp) {
                $totalSize += $size
            }
        }
        else {
            $size = (Get-Item $memoryDmp -ErrorAction SilentlyContinue).Length
            Write-Host "  $($script:GRAY)MEMORY.DMP ($(Format-ByteSize -Bytes $size)) - requires admin$($script:NC)"
        }
    }

    # Minidumps
    $minidumpPath = Join-Path $env:SystemRoot "Minidump"
    if (Test-Path $minidumpPath) {
        if (Test-IsElevated) {
            $size = Invoke-SafeClean -Path "$minidumpPath\*" -Description "Minidump files"
            $totalSize += $size
        }
        else {
            Write-Host "  $($script:GRAY)Minidumps require admin$($script:NC)"
        }
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

# ============================================================================
# Delivery Optimization Cache
# ============================================================================

function Clear-DeliveryOptimization {
    <#
    .SYNOPSIS
        Cleans Windows Delivery Optimization cache.
    #>
    Start-MoleSection -Title "Delivery Optimization"

    $doPath = Join-Path $env:SystemRoot "ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"

    if (-not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)Requires admin - skipping Delivery Optimization$($script:NC)"
        Stop-MoleSection
        return @{ CleanedSize = 0; RequiresAdmin = $true }
    }

    if (Test-Path $doPath) {
        $size = Invoke-SafeClean -Path "$doPath\*" -Description "Delivery Optimization cache"
        Stop-MoleSection
        return @{ CleanedSize = $size }
    }

    Stop-MoleSection
    return @{ CleanedSize = 0 }
}

# ============================================================================
# Windows Installer Cache
# ============================================================================

function Clear-WindowsInstallerCache {
    <#
    .SYNOPSIS
        Cleans orphaned Windows Installer patch files.
    .DESCRIPTION
        This is a careful operation - only removes obviously orphaned files.
    #>
    Start-MoleSection -Title "Windows Installer"

    # Note: We intentionally don't clean C:\Windows\Installer as it contains
    # required files for uninstallation. Only clean temp files.

    $installerTemp = Join-Path $env:SystemRoot "Installer\$PatchCache$"
    if (Test-Path $installerTemp -ErrorAction SilentlyContinue) {
        if (Test-IsElevated) {
            # Report size only, don't auto-clean
            $size = Get-PathSize -Path $installerTemp
            if ($size -gt 100MB) {
                Write-Host "  $($script:ICON_LIST) Installer patch cache: $(Format-ByteSize -Bytes $size)"
                Write-Host "    $($script:GRAY)Use Disk Cleanup for safe removal$($script:NC)"
            }
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Font Cache
# ============================================================================

function Clear-SystemFontCache {
    <#
    .SYNOPSIS
        Cleans system font cache.
    #>
    Start-MoleSection -Title "System Font Cache"

    if (-not (Test-IsElevated)) {
        Write-Host "  $($script:GRAY)Requires admin - skipping font cache$($script:NC)"
        Stop-MoleSection
        return
    }

    # Font cache service files
    $fontCachePath = Join-Path $env:SystemRoot "ServiceProfiles\LocalService\AppData\Local\FontCache"
    if (Test-Path $fontCachePath) {
        Invoke-SafeClean -Path "$fontCachePath\*" -Description "System font cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Windows Store Cache
# ============================================================================

function Clear-WindowsStoreCache {
    <#
    .SYNOPSIS
        Cleans Windows Store cache.
    #>
    Start-MoleSection -Title "Windows Store Cache"

    # User-level store cache
    $storeCache = Join-Path $env:LOCALAPPDATA "Packages\*Store*\LocalCache"
    $storeCaches = Get-ChildItem -Path $storeCache -ErrorAction SilentlyContinue

    foreach ($cache in $storeCaches) {
        Invoke-SafeClean -Path "$($cache.FullName)\*" -Description "Windows Store cache"
    }

    # Alternative: run wsreset (without the -i flag which opens Store)
    if (Get-MoleDryRun) {
        Write-MoleDryRun "Windows Store cache reset - would execute"
    }
    else {
        # Note: wsreset.exe clears the cache but also opens the Store app
        # We'll skip this and just clean the cache directories
    }

    Stop-MoleSection
}

# ============================================================================
# Temporary Internet Files
# ============================================================================

function Clear-IECache {
    <#
    .SYNOPSIS
        Cleans Internet Explorer / legacy Edge cache.
    #>
    Start-MoleSection -Title "Internet Explorer Cache"

    # INetCache
    $inetCache = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\INetCache"
    if (Test-Path $inetCache) {
        Invoke-SafeClean -Path "$inetCache\*" -Description "Internet cache"
    }

    # WebCache (WebCacheV01.dat etc.)
    $webCache = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WebCache"
    # Don't clean - these are locked and managed by Windows

    Stop-MoleSection
}

# ============================================================================
# Master Windows Cleanup Function
# ============================================================================

function Invoke-WindowsCleanup {
    <#
    .SYNOPSIS
        Performs all Windows-specific cleanup operations.
    .PARAMETER IncludeAdminTasks
        Include tasks that require admin privileges.
    .OUTPUTS
        Hashtable with total CleanedSize and AdminTasksSkipped count.
    #>
    param(
        [bool]$IncludeAdminTasks = $true
    )

    Write-MoleInfo "Starting Windows-specific cleanup..."

    $isAdmin = Test-IsElevated
    $adminSkipped = 0

    # Tasks that don't require admin
    Clear-DnsCache
    Clear-WindowsErrorReports
    Clear-WindowsStoreCache
    Clear-IECache

    # Tasks that require admin
    if ($IncludeAdminTasks) {
        if ($isAdmin) {
            Clear-WindowsUpdateCache
            Clear-SystemTemp
            Clear-PrefetchFiles
            Clear-MemoryDumps
            Clear-DeliveryOptimization
            Clear-SystemFontCache
            Clear-WindowsInstallerCache
        }
        else {
            Write-Host ""
            Write-Host "$($script:YELLOW)Some cleanup tasks were skipped (require administrator)$($script:NC)"
            Write-Host "$($script:GRAY)Run 'mole clean --admin' for full cleanup$($script:NC)"
            $adminSkipped = 7  # Number of admin tasks skipped
        }
    }

    return @{
        CleanedSize = 0
        AdminTasksSkipped = $adminSkipped
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Clear-WindowsUpdateCache'
    'Clear-SystemTemp'
    'Clear-WindowsErrorReports'
    'Clear-DnsCache'
    'Clear-PrefetchFiles'
    'Clear-MemoryDumps'
    'Clear-DeliveryOptimization'
    'Clear-WindowsInstallerCache'
    'Clear-SystemFontCache'
    'Clear-WindowsStoreCache'
    'Clear-IECache'
    'Invoke-WindowsCleanup'
)
