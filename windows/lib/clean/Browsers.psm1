# Mole Windows - Browser Cleanup Module
# Cleans browser caches for Chrome, Edge, Firefox, Brave, and others

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
if ($script:MOLE_CLEAN_BROWSERS_LOADED) { return }
$script:MOLE_CLEAN_BROWSERS_LOADED = $true

# ============================================================================
# Browser Detection
# ============================================================================

function Get-InstalledBrowsers {
    <#
    .SYNOPSIS
        Detects installed browsers and their data paths.
    .OUTPUTS
        Array of hashtables with browser info.
    #>
    $browsers = @()

    # Google Chrome
    $chromePath = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"
    if (Test-Path $chromePath) {
        $browsers += @{
            Name = "Google Chrome"
            ProcessName = "chrome"
            DataPath = $chromePath
            CachePaths = @(
                "Default\Cache",
                "Default\Code Cache",
                "Default\GPUCache",
                "Default\Service Worker\CacheStorage",
                "Default\Service Worker\ScriptCache",
                "ShaderCache",
                "GrShaderCache"
            )
        }
    }

    # Microsoft Edge
    $edgePath = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"
    if (Test-Path $edgePath) {
        $browsers += @{
            Name = "Microsoft Edge"
            ProcessName = "msedge"
            DataPath = $edgePath
            CachePaths = @(
                "Default\Cache",
                "Default\Code Cache",
                "Default\GPUCache",
                "Default\Service Worker\CacheStorage",
                "Default\Service Worker\ScriptCache",
                "ShaderCache",
                "GrShaderCache"
            )
        }
    }

    # Mozilla Firefox
    $firefoxPath = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        $browsers += @{
            Name = "Mozilla Firefox"
            ProcessName = "firefox"
            DataPath = $firefoxPath
            IsFirefox = $true
            CachePaths = @(
                "*\cache2",
                "*\jumpListCache",
                "*\OfflineCache",
                "*\startupCache",
                "*\thumbnails"
            )
        }
    }

    # Brave Browser
    $bravePath = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"
    if (Test-Path $bravePath) {
        $browsers += @{
            Name = "Brave Browser"
            ProcessName = "brave"
            DataPath = $bravePath
            CachePaths = @(
                "Default\Cache",
                "Default\Code Cache",
                "Default\GPUCache",
                "Default\Service Worker\CacheStorage",
                "ShaderCache"
            )
        }
    }

    # Opera
    $operaPath = Join-Path $env:APPDATA "Opera Software\Opera Stable"
    if (Test-Path $operaPath) {
        $browsers += @{
            Name = "Opera"
            ProcessName = "opera"
            DataPath = $operaPath
            CachePaths = @(
                "Cache",
                "Code Cache",
                "GPUCache",
                "ShaderCache"
            )
        }
    }

    # Vivaldi
    $vivaldiPath = Join-Path $env:LOCALAPPDATA "Vivaldi\User Data"
    if (Test-Path $vivaldiPath) {
        $browsers += @{
            Name = "Vivaldi"
            ProcessName = "vivaldi"
            DataPath = $vivaldiPath
            CachePaths = @(
                "Default\Cache",
                "Default\Code Cache",
                "Default\GPUCache",
                "ShaderCache"
            )
        }
    }

    # Arc Browser
    $arcPath = Join-Path $env:LOCALAPPDATA "Arc\User Data"
    if (Test-Path $arcPath) {
        $browsers += @{
            Name = "Arc"
            ProcessName = "Arc"
            DataPath = $arcPath
            CachePaths = @(
                "Default\Cache",
                "Default\Code Cache",
                "Default\GPUCache"
            )
        }
    }

    return $browsers
}

# ============================================================================
# Browser Cache Cleanup
# ============================================================================

function Clear-BrowserCache {
    <#
    .SYNOPSIS
        Cleans cache for a specific browser.
    .PARAMETER Browser
        The browser hashtable from Get-InstalledBrowsers.
    .PARAMETER Force
        Clean even if browser is running (will skip locked files).
    .OUTPUTS
        Hashtable with CleanedSize.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Browser,

        [switch]$Force
    )

    $results = @{
        CleanedSize = 0
        Skipped = $false
    }

    # Check if browser is running
    $isRunning = Test-ProcessRunning -ProcessName $Browser.ProcessName

    if ($isRunning -and -not $Force) {
        Write-MoleWarning "$($Browser.Name) is running - some files may be locked"
    }

    foreach ($cachePath in $Browser.CachePaths) {
        $fullPath = Join-Path $Browser.DataPath $cachePath

        # Handle wildcards for Firefox profiles
        if ($cachePath -match '\*') {
            $matchingPaths = Get-ChildItem -Path $Browser.DataPath -Filter ($cachePath -replace '\*\\', '') -Directory -ErrorAction SilentlyContinue
            foreach ($match in $matchingPaths) {
                $size = Invoke-SafeClean -Path "$($match.FullName)\*" -Description "$($Browser.Name) cache"
                $results.CleanedSize += $size
            }
        }
        elseif (Test-Path $fullPath) {
            $size = Invoke-SafeClean -Path "$fullPath\*" -Description "$($Browser.Name) cache"
            $results.CleanedSize += $size
        }
    }

    return $results
}

function Clear-ChromeCache {
    <#
    .SYNOPSIS
        Cleans Google Chrome cache.
    #>
    Start-MoleSection -Title "Google Chrome"

    $chromePath = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data"

    if (-not (Test-Path $chromePath)) {
        Stop-MoleSection
        return @{ CleanedSize = 0 }
    }

    $totalSize = 0

    # Get all profile directories (Default, Profile 1, Profile 2, etc.)
    $profiles = @("Default") + @(Get-ChildItem -Path $chromePath -Filter "Profile *" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

    foreach ($profile in $profiles) {
        $profilePath = Join-Path $chromePath $profile

        if (Test-Path $profilePath) {
            # Standard cache directories
            $cacheDirs = @(
                "Cache\Cache_Data",
                "Code Cache",
                "GPUCache",
                "Service Worker\CacheStorage",
                "Service Worker\ScriptCache"
            )

            foreach ($cacheDir in $cacheDirs) {
                $path = Join-Path $profilePath $cacheDir
                if (Test-Path $path) {
                    $size = Invoke-SafeClean -Path "$path\*" -Description "Chrome $profile cache"
                    $totalSize += $size
                }
            }
        }
    }

    # Shader cache (shared)
    $shaderCache = Join-Path $chromePath "ShaderCache"
    if (Test-Path $shaderCache) {
        $size = Invoke-SafeClean -Path "$shaderCache\*" -Description "Chrome shader cache"
        $totalSize += $size
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

function Clear-EdgeCache {
    <#
    .SYNOPSIS
        Cleans Microsoft Edge cache.
    #>
    Start-MoleSection -Title "Microsoft Edge"

    $edgePath = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data"

    if (-not (Test-Path $edgePath)) {
        Stop-MoleSection
        return @{ CleanedSize = 0 }
    }

    $totalSize = 0

    # Get all profile directories
    $profiles = @("Default") + @(Get-ChildItem -Path $edgePath -Filter "Profile *" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

    foreach ($profile in $profiles) {
        $profilePath = Join-Path $edgePath $profile

        if (Test-Path $profilePath) {
            $cacheDirs = @(
                "Cache\Cache_Data",
                "Code Cache",
                "GPUCache",
                "Service Worker\CacheStorage",
                "Service Worker\ScriptCache"
            )

            foreach ($cacheDir in $cacheDirs) {
                $path = Join-Path $profilePath $cacheDir
                if (Test-Path $path) {
                    $size = Invoke-SafeClean -Path "$path\*" -Description "Edge $profile cache"
                    $totalSize += $size
                }
            }
        }
    }

    # Shader cache
    $shaderCache = Join-Path $edgePath "ShaderCache"
    if (Test-Path $shaderCache) {
        $size = Invoke-SafeClean -Path "$shaderCache\*" -Description "Edge shader cache"
        $totalSize += $size
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

function Clear-FirefoxCache {
    <#
    .SYNOPSIS
        Cleans Mozilla Firefox cache.
    #>
    Start-MoleSection -Title "Mozilla Firefox"

    $firefoxPath = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"

    if (-not (Test-Path $firefoxPath)) {
        # Try local app data location
        $firefoxPath = Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles"
        if (-not (Test-Path $firefoxPath)) {
            Stop-MoleSection
            return @{ CleanedSize = 0 }
        }
    }

    $totalSize = 0

    # Get all Firefox profiles
    $profiles = Get-ChildItem -Path $firefoxPath -Directory -ErrorAction SilentlyContinue

    foreach ($profile in $profiles) {
        $cacheDirs = @(
            "cache2\entries",
            "cache2\doomed",
            "jumpListCache",
            "OfflineCache",
            "startupCache",
            "thumbnails"
        )

        foreach ($cacheDir in $cacheDirs) {
            $path = Join-Path $profile.FullName $cacheDir
            if (Test-Path $path) {
                $size = Invoke-SafeClean -Path "$path\*" -Description "Firefox cache"
                $totalSize += $size
            }
        }
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

function Clear-BraveCache {
    <#
    .SYNOPSIS
        Cleans Brave browser cache.
    #>
    Start-MoleSection -Title "Brave Browser"

    $bravePath = Join-Path $env:LOCALAPPDATA "BraveSoftware\Brave-Browser\User Data"

    if (-not (Test-Path $bravePath)) {
        Stop-MoleSection
        return @{ CleanedSize = 0 }
    }

    $totalSize = 0

    $profiles = @("Default") + @(Get-ChildItem -Path $bravePath -Filter "Profile *" -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)

    foreach ($profile in $profiles) {
        $profilePath = Join-Path $bravePath $profile

        if (Test-Path $profilePath) {
            $cacheDirs = @(
                "Cache\Cache_Data",
                "Code Cache",
                "GPUCache",
                "Service Worker\CacheStorage"
            )

            foreach ($cacheDir in $cacheDirs) {
                $path = Join-Path $profilePath $cacheDir
                if (Test-Path $path) {
                    $size = Invoke-SafeClean -Path "$path\*" -Description "Brave $profile cache"
                    $totalSize += $size
                }
            }
        }
    }

    Stop-MoleSection
    return @{ CleanedSize = $totalSize }
}

# ============================================================================
# Browser History & Cookies (Optional - User Opt-in)
# ============================================================================

function Clear-BrowserHistory {
    <#
    .SYNOPSIS
        Clears browser history (requires explicit user consent).
    .PARAMETER BrowserName
        Name of the browser to clear history for.
    .DESCRIPTION
        This is a destructive operation that clears browsing history.
        Should only be called with explicit user consent.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Chrome", "Edge", "Firefox", "Brave", "All")]
        [string]$BrowserName
    )

    Write-MoleWarning "Clearing browser history is a destructive operation"
    Write-MoleWarning "This will clear your browsing history permanently"

    # This is intentionally not implemented in the MVP
    # History cleanup should be done through browser settings
    Write-MoleInfo "Please use your browser's built-in history clearing feature"
}

# ============================================================================
# Master Browser Cleanup Function
# ============================================================================

function Invoke-BrowserCleanup {
    <#
    .SYNOPSIS
        Performs cleanup for all installed browsers.
    .PARAMETER WarnIfRunning
        Show warning if browsers are running (default: true).
    .OUTPUTS
        Hashtable with total CleanedSize.
    #>
    param(
        [bool]$WarnIfRunning = $true
    )

    Write-MoleInfo "Starting browser cache cleanup..."

    $totalSize = 0

    # Check for running browsers
    if ($WarnIfRunning) {
        $runningBrowsers = @()
        $browserProcesses = @("chrome", "msedge", "firefox", "brave", "opera", "vivaldi")

        foreach ($proc in $browserProcesses) {
            if (Test-ProcessRunning -ProcessName $proc) {
                $runningBrowsers += $proc
            }
        }

        if ($runningBrowsers.Count -gt 0) {
            Write-MoleWarning "The following browsers are running: $($runningBrowsers -join ', ')"
            Write-MoleWarning "Some cache files may be locked and will be skipped"
        }
    }

    # Clean each browser
    $result = Clear-ChromeCache
    $totalSize += $result.CleanedSize

    $result = Clear-EdgeCache
    $totalSize += $result.CleanedSize

    $result = Clear-FirefoxCache
    $totalSize += $result.CleanedSize

    $result = Clear-BraveCache
    $totalSize += $result.CleanedSize

    return @{
        CleanedSize = $totalSize
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Get-InstalledBrowsers'
    'Clear-BrowserCache'
    'Clear-ChromeCache'
    'Clear-EdgeCache'
    'Clear-FirefoxCache'
    'Clear-BraveCache'
    'Clear-BrowserHistory'
    'Invoke-BrowserCleanup'
)
