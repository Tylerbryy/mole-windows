# Mole Windows - Developer Tools Cleanup Module
# Cleans caches for npm, pip, cargo, gradle, go, docker, and other dev tools

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
if ($script:MOLE_CLEAN_DEV_LOADED) { return }
$script:MOLE_CLEAN_DEV_LOADED = $true

# ============================================================================
# npm/pnpm/yarn/bun Cleanup
# ============================================================================

function Clear-NpmCache {
    <#
    .SYNOPSIS
        Cleans npm, pnpm, yarn, and bun caches.
    #>
    Start-MoleSection -Title "Node.js Package Managers"

    # npm cache
    $npmCache = Join-Path $env:LOCALAPPDATA "npm-cache"
    if (-not (Test-Path $npmCache)) {
        $npmCache = Join-Path $env:APPDATA "npm-cache"
    }
    if (Test-Path $npmCache) {
        if (Get-MoleDryRun) {
            $size = Get-PathSize -Path $npmCache
            Write-MoleDryRun "npm cache - would clean $(Format-ByteSize -Bytes $size)"
        }
        else {
            # Use npm cache clean if available
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                try {
                    npm cache clean --force 2>$null
                    Set-MoleActivity
                    Write-MoleSuccess "npm cache cleaned"
                }
                catch {
                    Invoke-SafeClean -Path "$npmCache\*" -Description "npm cache"
                }
            }
            else {
                Invoke-SafeClean -Path "$npmCache\*" -Description "npm cache"
            }
        }
    }

    # pnpm store
    $pnpmStore = Join-Path $env:LOCALAPPDATA "pnpm\store"
    if (-not (Test-Path $pnpmStore)) {
        $pnpmStore = Join-Path $env:USERPROFILE ".pnpm-store"
    }
    if (Test-Path $pnpmStore) {
        if (Get-Command pnpm -ErrorAction SilentlyContinue) {
            if (Get-MoleDryRun) {
                $size = Get-PathSize -Path $pnpmStore
                Write-MoleDryRun "pnpm store - would clean $(Format-ByteSize -Bytes $size)"
            }
            else {
                try {
                    pnpm store prune 2>$null
                    Set-MoleActivity
                    Write-MoleSuccess "pnpm store pruned"
                }
                catch {
                    Write-MoleDebug "pnpm store prune failed: $($_.Exception.Message)"
                }
            }
        }
    }

    # yarn cache
    $yarnCache = Join-Path $env:LOCALAPPDATA "Yarn\Cache"
    if (-not (Test-Path $yarnCache)) {
        $yarnCache = Join-Path $env:USERPROFILE ".cache\yarn"
    }
    if (Test-Path $yarnCache) {
        Invoke-SafeClean -Path "$yarnCache\*" -Description "Yarn cache"
    }

    # bun cache
    $bunCache = Join-Path $env:USERPROFILE ".bun\install\cache"
    if (Test-Path $bunCache) {
        Invoke-SafeClean -Path "$bunCache\*" -Description "Bun cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Python/pip Cleanup
# ============================================================================

function Clear-PythonCache {
    <#
    .SYNOPSIS
        Cleans pip, pyenv, poetry, and other Python tool caches.
    #>
    Start-MoleSection -Title "Python Package Managers"

    # pip cache
    $pipCache = Join-Path $env:LOCALAPPDATA "pip\Cache"
    if (Test-Path $pipCache) {
        if (Get-MoleDryRun) {
            $size = Get-PathSize -Path $pipCache
            Write-MoleDryRun "pip cache - would clean $(Format-ByteSize -Bytes $size)"
        }
        else {
            if (Get-Command pip3 -ErrorAction SilentlyContinue) {
                try {
                    pip3 cache purge 2>$null
                    Set-MoleActivity
                    Write-MoleSuccess "pip cache purged"
                }
                catch {
                    Invoke-SafeClean -Path "$pipCache\*" -Description "pip cache"
                }
            }
            elseif (Get-Command pip -ErrorAction SilentlyContinue) {
                try {
                    pip cache purge 2>$null
                    Set-MoleActivity
                    Write-MoleSuccess "pip cache purged"
                }
                catch {
                    Invoke-SafeClean -Path "$pipCache\*" -Description "pip cache"
                }
            }
            else {
                Invoke-SafeClean -Path "$pipCache\*" -Description "pip cache"
            }
        }
    }

    # pyenv cache
    $pyenvCache = Join-Path $env:USERPROFILE ".pyenv\cache"
    if (Test-Path $pyenvCache) {
        Invoke-SafeClean -Path "$pyenvCache\*" -Description "pyenv cache"
    }

    # poetry cache
    $poetryCache = Join-Path $env:LOCALAPPDATA "pypoetry\Cache"
    if (-not (Test-Path $poetryCache)) {
        $poetryCache = Join-Path $env:USERPROFILE ".cache\pypoetry"
    }
    if (Test-Path $poetryCache) {
        Invoke-SafeClean -Path "$poetryCache\*" -Description "Poetry cache"
    }

    # uv cache
    $uvCache = Join-Path $env:LOCALAPPDATA "uv\cache"
    if (-not (Test-Path $uvCache)) {
        $uvCache = Join-Path $env:USERPROFILE ".cache\uv"
    }
    if (Test-Path $uvCache) {
        Invoke-SafeClean -Path "$uvCache\*" -Description "uv cache"
    }

    # pytest cache
    $pytestCache = Join-Path $env:USERPROFILE ".pytest_cache"
    if (Test-Path $pytestCache) {
        Invoke-SafeClean -Path "$pytestCache\*" -Description "Pytest cache"
    }

    # mypy cache
    $mypyCache = Join-Path $env:USERPROFILE ".mypy_cache"
    if (Test-Path $mypyCache) {
        Invoke-SafeClean -Path "$mypyCache\*" -Description "MyPy cache"
    }

    # ruff cache
    $ruffCache = Join-Path $env:LOCALAPPDATA "ruff\cache"
    if (-not (Test-Path $ruffCache)) {
        $ruffCache = Join-Path $env:USERPROFILE ".cache\ruff"
    }
    if (Test-Path $ruffCache) {
        Invoke-SafeClean -Path "$ruffCache\*" -Description "Ruff cache"
    }

    # Conda packages cache
    $condaCache = Join-Path $env:USERPROFILE ".conda\pkgs"
    if (Test-Path $condaCache) {
        Invoke-SafeClean -Path "$condaCache\*" -Description "Conda packages cache"
    }

    # Anaconda packages cache
    $anacondaCache = Join-Path $env:USERPROFILE "anaconda3\pkgs"
    if (Test-Path $anacondaCache) {
        Invoke-SafeClean -Path "$anacondaCache\*" -Description "Anaconda packages cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Go Cleanup
# ============================================================================

function Clear-GoCache {
    <#
    .SYNOPSIS
        Cleans Go build and module caches.
    #>
    Start-MoleSection -Title "Go Cache"

    if (Get-Command go -ErrorAction SilentlyContinue) {
        if (Get-MoleDryRun) {
            # Calculate size
            $goCachePath = & go env GOCACHE 2>$null
            $goModCachePath = & go env GOMODCACHE 2>$null

            $totalSize = 0
            if ($goCachePath -and (Test-Path $goCachePath)) {
                $totalSize += Get-PathSize -Path $goCachePath
            }
            if ($goModCachePath -and (Test-Path $goModCachePath)) {
                $totalSize += Get-PathSize -Path $goModCachePath
            }

            if ($totalSize -gt 0) {
                Write-MoleDryRun "Go cache - would clean $(Format-ByteSize -Bytes $totalSize)"
            }
        }
        else {
            try {
                go clean -cache 2>$null
                go clean -modcache 2>$null
                Set-MoleActivity
                Write-MoleSuccess "Go cache cleaned"
            }
            catch {
                Write-MoleDebug "Go cache clean failed: $($_.Exception.Message)"
            }
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Rust/Cargo Cleanup
# ============================================================================

function Clear-RustCache {
    <#
    .SYNOPSIS
        Cleans Rust cargo and rustup caches.
    #>
    Start-MoleSection -Title "Rust/Cargo Cache"

    # Cargo registry cache
    $cargoCache = Join-Path $env:USERPROFILE ".cargo\registry\cache"
    if (Test-Path $cargoCache) {
        Invoke-SafeClean -Path "$cargoCache\*" -Description "Cargo registry cache"
    }

    # Cargo git cache
    $cargoGit = Join-Path $env:USERPROFILE ".cargo\git"
    if (Test-Path $cargoGit) {
        Invoke-SafeClean -Path "$cargoGit\db\*" -Description "Cargo git cache"
    }

    # Rustup downloads
    $rustupDownloads = Join-Path $env:USERPROFILE ".rustup\downloads"
    if (Test-Path $rustupDownloads) {
        Invoke-SafeClean -Path "$rustupDownloads\*" -Description "Rustup downloads"
    }

    # Check for multiple toolchains
    $toolchainsPath = Join-Path $env:USERPROFILE ".rustup\toolchains"
    if (Test-Path $toolchainsPath) {
        $toolchains = Get-ChildItem -Path $toolchainsPath -Directory -ErrorAction SilentlyContinue
        if ($toolchains.Count -gt 1) {
            Set-MoleActivity
            Write-Host "  Found $($script:GREEN)$($toolchains.Count)$($script:NC) Rust toolchains"
            Write-Host "  You can list them with: $($script:GRAY)rustup toolchain list$($script:NC)"
            Write-Host "  Remove unused with: $($script:GRAY)rustup toolchain uninstall <name>$($script:NC)"
        }
    }

    Stop-MoleSection
}

# ============================================================================
# Docker Cleanup
# ============================================================================

function Clear-DockerCache {
    <#
    .SYNOPSIS
        Cleans Docker build cache and dangling images.
    #>
    Start-MoleSection -Title "Docker Cache"

    if (Get-Command docker -ErrorAction SilentlyContinue) {
        # Check if Docker daemon is running
        $dockerRunning = $false
        try {
            $null = docker info 2>$null
            $dockerRunning = $true
        }
        catch {
            Write-MoleDebug "Docker daemon not running, skipping Docker cleanup"
        }

        if ($dockerRunning) {
            if (Get-MoleDryRun) {
                Set-MoleActivity
                Write-MoleDryRun "Docker build cache - would clean"
            }
            else {
                try {
                    docker builder prune -af 2>$null
                    Set-MoleActivity
                    Write-MoleSuccess "Docker build cache cleaned"
                }
                catch {
                    Write-MoleDebug "Docker builder prune failed: $($_.Exception.Message)"
                }
            }
        }
    }

    # Docker Desktop cache (Windows specific)
    $dockerCache = Join-Path $env:LOCALAPPDATA "Docker\wsl\data"
    # Note: Don't clean the WSL data, just log its size
    if (Test-Path $dockerCache) {
        $size = Get-PathSize -Path $dockerCache
        if ($size -gt 1GB) {
            Write-Host "  $($script:ICON_LIST) Docker WSL disk: $(Format-ByteSize -Bytes $size)"
            Write-Host "    $($script:GRAY)Reclaim space via Docker Desktop settings$($script:NC)"
        }
    }

    Stop-MoleSection
}

# ============================================================================
# JVM Ecosystem Cleanup
# ============================================================================

function Clear-JvmCache {
    <#
    .SYNOPSIS
        Cleans Gradle, Maven, SBT, and Ivy caches.
    #>
    Start-MoleSection -Title "JVM Ecosystem"

    # Gradle caches
    $gradleCache = Join-Path $env:USERPROFILE ".gradle\caches"
    if (Test-Path $gradleCache) {
        Invoke-SafeClean -Path "$gradleCache\*" -Description "Gradle caches"
    }

    # Gradle daemon logs
    $gradleDaemon = Join-Path $env:USERPROFILE ".gradle\daemon"
    if (Test-Path $gradleDaemon) {
        Invoke-SafeClean -Path "$gradleDaemon\*" -Description "Gradle daemon logs"
    }

    # Maven repository (be careful - this is also a local repo)
    # Only clean the resolved-guava-versions.xml and similar cache files
    $mavenCache = Join-Path $env:USERPROFILE ".m2\repository"
    if (Test-Path $mavenCache) {
        # Just report size, don't auto-clean Maven repo
        $size = Get-PathSize -Path $mavenCache
        if ($size -gt 100MB) {
            Write-Host "  $($script:ICON_LIST) Maven repository: $(Format-ByteSize -Bytes $size)"
            Write-Host "    $($script:GRAY)Clean manually if needed$($script:NC)"
        }
    }

    # SBT cache
    $sbtCache = Join-Path $env:USERPROFILE ".sbt"
    if (Test-Path $sbtCache) {
        Invoke-SafeClean -Path "$sbtCache\*.log" -Description "SBT logs"
        Invoke-SafeClean -Path "$sbtCache\boot\*" -Description "SBT boot cache"
    }

    # Ivy cache
    $ivyCache = Join-Path $env:USERPROFILE ".ivy2\cache"
    if (Test-Path $ivyCache) {
        Invoke-SafeClean -Path "$ivyCache\*" -Description "Ivy cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Frontend Build Tools
# ============================================================================

function Clear-FrontendCache {
    <#
    .SYNOPSIS
        Cleans TypeScript, Webpack, Vite, Turbo, and other frontend tool caches.
    #>
    Start-MoleSection -Title "Frontend Build Tools"

    # TypeScript cache
    $tsCache = Join-Path $env:USERPROFILE ".cache\typescript"
    if (Test-Path $tsCache) {
        Invoke-SafeClean -Path "$tsCache\*" -Description "TypeScript cache"
    }

    # Turbo cache
    $turboCache = Join-Path $env:USERPROFILE ".turbo"
    if (Test-Path $turboCache) {
        Invoke-SafeClean -Path "$turboCache\*" -Description "Turbo cache"
    }

    # Vite cache
    $viteCache = Join-Path $env:USERPROFILE ".vite"
    if (Test-Path $viteCache) {
        Invoke-SafeClean -Path "$viteCache\*" -Description "Vite cache"
    }

    # Parcel cache
    $parcelCache = Join-Path $env:USERPROFILE ".parcel-cache"
    if (Test-Path $parcelCache) {
        Invoke-SafeClean -Path "$parcelCache\*" -Description "Parcel cache"
    }

    # ESLint cache
    $eslintCache = Join-Path $env:USERPROFILE ".eslintcache"
    if (Test-Path $eslintCache) {
        Invoke-SafeClean -Path $eslintCache -Description "ESLint cache"
    }

    # node-gyp cache
    $nodeGypCache = Join-Path $env:LOCALAPPDATA "node-gyp\Cache"
    if (-not (Test-Path $nodeGypCache)) {
        $nodeGypCache = Join-Path $env:USERPROFILE ".node-gyp"
    }
    if (Test-Path $nodeGypCache) {
        Invoke-SafeClean -Path "$nodeGypCache\*" -Description "node-gyp cache"
    }

    # Electron cache
    $electronCache = Join-Path $env:LOCALAPPDATA "electron\Cache"
    if (-not (Test-Path $electronCache)) {
        $electronCache = Join-Path $env:USERPROFILE ".cache\electron"
    }
    if (Test-Path $electronCache) {
        Invoke-SafeClean -Path "$electronCache\*" -Description "Electron cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Cloud & DevOps Tools
# ============================================================================

function Clear-CloudToolsCache {
    <#
    .SYNOPSIS
        Cleans Kubernetes, AWS, Azure, GCloud, and Terraform caches.
    #>
    Start-MoleSection -Title "Cloud & DevOps Tools"

    # Kubernetes cache
    $kubeCache = Join-Path $env:USERPROFILE ".kube\cache"
    if (Test-Path $kubeCache) {
        Invoke-SafeClean -Path "$kubeCache\*" -Description "Kubernetes cache"
    }

    # AWS CLI cache
    $awsCache = Join-Path $env:USERPROFILE ".aws\cli\cache"
    if (Test-Path $awsCache) {
        Invoke-SafeClean -Path "$awsCache\*" -Description "AWS CLI cache"
    }

    # Azure CLI cache/logs
    $azureLogs = Join-Path $env:USERPROFILE ".azure\logs"
    if (Test-Path $azureLogs) {
        Invoke-SafeClean -Path "$azureLogs\*" -Description "Azure CLI logs"
    }

    # Google Cloud logs
    $gcloudLogs = Join-Path $env:APPDATA "gcloud\logs"
    if (Test-Path $gcloudLogs) {
        Invoke-SafeClean -Path "$gcloudLogs\*" -Description "Google Cloud logs"
    }

    # Terraform cache (plugin cache, not state!)
    $terraformCache = Join-Path $env:USERPROFILE ".terraform.d\plugin-cache"
    if (Test-Path $terraformCache) {
        Invoke-SafeClean -Path "$terraformCache\*" -Description "Terraform plugin cache"
    }

    # Helm cache
    $helmCache = Join-Path $env:LOCALAPPDATA "helm\cache"
    if (Test-Path $helmCache) {
        Invoke-SafeClean -Path "$helmCache\*" -Description "Helm cache"
    }

    Stop-MoleSection
}

# ============================================================================
# IDE & Editor Caches
# ============================================================================

function Clear-IdeCache {
    <#
    .SYNOPSIS
        Cleans VS Code, JetBrains, and other IDE caches.
    #>
    Start-MoleSection -Title "IDE & Editor Caches"

    # VS Code caches (not settings!)
    $vscodeCacheDir = Join-Path $env:APPDATA "Code\Cache"
    if (Test-Path $vscodeCacheDir) {
        Invoke-SafeClean -Path "$vscodeCacheDir\*" -Description "VS Code cache"
    }

    $vscodeCachedData = Join-Path $env:APPDATA "Code\CachedData"
    if (Test-Path $vscodeCachedData) {
        Invoke-SafeClean -Path "$vscodeCachedData\*" -Description "VS Code cached data"
    }

    $vscodeGPUCache = Join-Path $env:APPDATA "Code\GPUCache"
    if (Test-Path $vscodeGPUCache) {
        Invoke-SafeClean -Path "$vscodeGPUCache\*" -Description "VS Code GPU cache"
    }

    # VS Code Insiders
    $vscodeInsidersCache = Join-Path $env:APPDATA "Code - Insiders\Cache"
    if (Test-Path $vscodeInsidersCache) {
        Invoke-SafeClean -Path "$vscodeInsidersCache\*" -Description "VS Code Insiders cache"
    }

    # Cursor
    $cursorCache = Join-Path $env:APPDATA "Cursor\Cache"
    if (Test-Path $cursorCache) {
        Invoke-SafeClean -Path "$cursorCache\*" -Description "Cursor cache"
    }

    # JetBrains IDE caches (in LocalAppData)
    $jetbrainsCache = Join-Path $env:LOCALAPPDATA "JetBrains"
    if (Test-Path $jetbrainsCache) {
        # Clean caches subdirectory in each IDE folder
        $ideDataDirs = Get-ChildItem -Path $jetbrainsCache -Directory -ErrorAction SilentlyContinue
        foreach ($ideDir in $ideDataDirs) {
            $cacheDir = Join-Path $ideDir.FullName "caches"
            if (Test-Path $cacheDir) {
                Invoke-SafeClean -Path "$cacheDir\*" -Description "JetBrains $($ideDir.Name) cache"
            }
        }
    }

    # Sublime Text cache
    $sublimeCache = Join-Path $env:APPDATA "Sublime Text\Cache"
    if (Test-Path $sublimeCache) {
        Invoke-SafeClean -Path "$sublimeCache\*" -Description "Sublime Text cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Other Languages
# ============================================================================

function Clear-OtherLangCache {
    <#
    .SYNOPSIS
        Cleans caches for Ruby, PHP, .NET, Deno, and other languages.
    #>
    Start-MoleSection -Title "Other Languages"

    # Ruby Bundler cache
    $bundlerCache = Join-Path $env:USERPROFILE ".bundle\cache"
    if (Test-Path $bundlerCache) {
        Invoke-SafeClean -Path "$bundlerCache\*" -Description "Ruby Bundler cache"
    }

    # PHP Composer cache
    $composerCache = Join-Path $env:LOCALAPPDATA "Composer\cache"
    if (-not (Test-Path $composerCache)) {
        $composerCache = Join-Path $env:APPDATA "Composer\cache"
    }
    if (Test-Path $composerCache) {
        Invoke-SafeClean -Path "$composerCache\*" -Description "PHP Composer cache"
    }

    # NuGet cache
    $nugetCache = Join-Path $env:LOCALAPPDATA "NuGet\v3-cache"
    if (Test-Path $nugetCache) {
        Invoke-SafeClean -Path "$nugetCache\*" -Description "NuGet cache"
    }

    # Deno cache
    $denoCache = Join-Path $env:LOCALAPPDATA "deno"
    if (Test-Path $denoCache) {
        Invoke-SafeClean -Path "$denoCache\deps\*" -Description "Deno deps cache"
        Invoke-SafeClean -Path "$denoCache\gen\*" -Description "Deno gen cache"
    }

    # Zig cache
    $zigCache = Join-Path $env:LOCALAPPDATA "zig"
    if (Test-Path $zigCache) {
        Invoke-SafeClean -Path "$zigCache\*" -Description "Zig cache"
    }

    # Dart/Flutter pub cache
    $pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache"
    if (Test-Path $pubCache) {
        Invoke-SafeClean -Path "$pubCache\*" -Description "Dart Pub cache"
    }

    Stop-MoleSection
}

# ============================================================================
# Master Developer Tools Cleanup Function
# ============================================================================

function Invoke-DevCleanup {
    <#
    .SYNOPSIS
        Performs all developer tools cleanup operations.
    .OUTPUTS
        Hashtable with total CleanedSize.
    #>
    Write-MoleInfo "Starting developer tools cleanup..."

    Clear-NpmCache
    Clear-PythonCache
    Clear-GoCache
    Clear-RustCache
    Clear-DockerCache
    Clear-JvmCache
    Clear-FrontendCache
    Clear-CloudToolsCache
    Clear-IdeCache
    Clear-OtherLangCache

    return @{
        CleanedSize = 0  # Size tracking would require more integration
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Clear-NpmCache'
    'Clear-PythonCache'
    'Clear-GoCache'
    'Clear-RustCache'
    'Clear-DockerCache'
    'Clear-JvmCache'
    'Clear-FrontendCache'
    'Clear-CloudToolsCache'
    'Clear-IdeCache'
    'Clear-OtherLangCache'
    'Invoke-DevCleanup'
)
