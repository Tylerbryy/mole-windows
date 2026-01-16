# Mole Windows - Whitelist Management
# Manages protected paths that should not be cleaned

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
if ($script:MOLE_WHITELIST_LOADED) { return }
$script:MOLE_WHITELIST_LOADED = $true

# ============================================================================
# Whitelist Configuration
# ============================================================================
$script:WHITELIST_FILE = Join-Path (Get-MoleConfigDir) "whitelist"

# ============================================================================
# Predefined Cache Items
# ============================================================================

function Get-AllCacheItems {
    <#
    .SYNOPSIS
        Returns all predefined cache items with their patterns.
    .OUTPUTS
        Array of hashtables with DisplayName, Pattern, Category.
    #>
    return @(
        # Browser Caches
        @{ DisplayName = "Google Chrome cache"; Pattern = "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache*"; Category = "browser_cache" }
        @{ DisplayName = "Microsoft Edge cache"; Pattern = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache*"; Category = "browser_cache" }
        @{ DisplayName = "Mozilla Firefox cache"; Pattern = "$env:APPDATA\Mozilla\Firefox\Profiles\*\cache2*"; Category = "browser_cache" }
        @{ DisplayName = "Brave browser cache"; Pattern = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache*"; Category = "browser_cache" }

        # IDE Caches
        @{ DisplayName = "VS Code cached data"; Pattern = "$env:APPDATA\Code\CachedData\*"; Category = "ide_cache" }
        @{ DisplayName = "VS Code cache"; Pattern = "$env:APPDATA\Code\Cache\*"; Category = "ide_cache" }
        @{ DisplayName = "JetBrains IDE caches"; Pattern = "$env:LOCALAPPDATA\JetBrains\*\caches\*"; Category = "ide_cache" }
        @{ DisplayName = "JetBrains IDE data"; Pattern = "$env:APPDATA\JetBrains\*"; Category = "ide_cache" }
        @{ DisplayName = "Cursor cache"; Pattern = "$env:APPDATA\Cursor\Cache\*"; Category = "ide_cache" }

        # Package Manager Caches
        @{ DisplayName = "npm cache"; Pattern = "$env:LOCALAPPDATA\npm-cache\*"; Category = "package_manager" }
        @{ DisplayName = "Yarn cache"; Pattern = "$env:LOCALAPPDATA\Yarn\Cache\*"; Category = "package_manager" }
        @{ DisplayName = "pnpm store"; Pattern = "$env:LOCALAPPDATA\pnpm\store\*"; Category = "package_manager" }
        @{ DisplayName = "pip cache"; Pattern = "$env:LOCALAPPDATA\pip\Cache\*"; Category = "package_manager" }
        @{ DisplayName = "NuGet cache"; Pattern = "$env:LOCALAPPDATA\NuGet\v3-cache\*"; Category = "package_manager" }
        @{ DisplayName = "Composer cache"; Pattern = "$env:LOCALAPPDATA\Composer\cache\*"; Category = "package_manager" }

        # Compiler Caches
        @{ DisplayName = "Cargo registry cache"; Pattern = "$env:USERPROFILE\.cargo\registry\cache\*"; Category = "compiler_cache" }
        @{ DisplayName = "Gradle caches"; Pattern = "$env:USERPROFILE\.gradle\caches\*"; Category = "compiler_cache" }
        @{ DisplayName = "Maven repository"; Pattern = "$env:USERPROFILE\.m2\repository\*"; Category = "compiler_cache" }

        # AI/ML Caches
        @{ DisplayName = "HuggingFace models"; Pattern = "$env:USERPROFILE\.cache\huggingface\*"; Category = "ai_ml_cache" }
        @{ DisplayName = "Ollama models"; Pattern = "$env:USERPROFILE\.ollama\models\*"; Category = "ai_ml_cache" }
        @{ DisplayName = "PyTorch cache"; Pattern = "$env:USERPROFILE\.cache\torch\*"; Category = "ai_ml_cache" }

        # System Caches
        @{ DisplayName = "User temp files"; Pattern = "$env:TEMP\*"; Category = "system_cache" }
        @{ DisplayName = "Windows thumbnail cache"; Pattern = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*"; Category = "system_cache" }
        @{ DisplayName = "Windows error reports"; Pattern = "$env:LOCALAPPDATA\Microsoft\Windows\WER\*"; Category = "system_cache" }
        @{ DisplayName = "Recycle Bin"; Pattern = "RECYCLE_BIN"; Category = "system_cache" }

        # Cloud Storage (protected by default)
        @{ DisplayName = "OneDrive data"; Pattern = "$env:LOCALAPPDATA\Microsoft\OneDrive\*"; Category = "cloud_storage" }
        @{ DisplayName = "Dropbox data"; Pattern = "$env:LOCALAPPDATA\Dropbox\*"; Category = "cloud_storage" }
        @{ DisplayName = "Google Drive data"; Pattern = "$env:LOCALAPPDATA\Google\DriveFS\*"; Category = "cloud_storage" }
    )
}

# ============================================================================
# Whitelist File Management
# ============================================================================

function Get-WhitelistPatterns {
    <#
    .SYNOPSIS
        Loads whitelist patterns from the config file.
    .OUTPUTS
        Array of pattern strings.
    #>
    Ensure-MoleConfigDir

    if (-not (Test-Path $script:WHITELIST_FILE)) {
        # Return default patterns if no config exists
        return $script:DEFAULT_WHITELIST_PATTERNS
    }

    $patterns = @()

    try {
        $content = Get-Content -Path $script:WHITELIST_FILE -ErrorAction Stop

        foreach ($line in $content) {
            # Skip empty lines and comments
            $trimmed = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed.StartsWith('#')) { continue }

            $patterns += $trimmed
        }
    }
    catch {
        Write-MoleDebug "Error reading whitelist: $($_.Exception.Message)"
        return $script:DEFAULT_WHITELIST_PATTERNS
    }

    # Merge with defaults if empty
    if ($patterns.Count -eq 0) {
        return $script:DEFAULT_WHITELIST_PATTERNS
    }

    return $patterns
}

function Save-WhitelistPatterns {
    <#
    .SYNOPSIS
        Saves whitelist patterns to the config file.
    .PARAMETER Patterns
        Array of patterns to save.
    #>
    param(
        [string[]]$Patterns
    )

    Ensure-MoleConfigDir

    $header = @"
# Mole Whitelist - Protected paths won't be deleted
# Add one pattern per line to keep items safe.
# Supports wildcards: * (any characters), ? (single character)
#
"@

    $content = $header

    # Remove duplicates
    $uniquePatterns = $Patterns | Select-Object -Unique

    foreach ($pattern in $uniquePatterns) {
        if (-not [string]::IsNullOrWhiteSpace($pattern)) {
            $content += "$pattern`n"
        }
    }

    try {
        Set-Content -Path $script:WHITELIST_FILE -Value $content -Force
        Write-MoleDebug "Whitelist saved with $($uniquePatterns.Count) patterns"
    }
    catch {
        Write-MoleError "Failed to save whitelist: $($_.Exception.Message)"
    }
}

function Add-WhitelistPattern {
    <#
    .SYNOPSIS
        Adds a pattern to the whitelist.
    .PARAMETER Pattern
        The pattern to add.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $patterns = Get-WhitelistPatterns
    $patterns += $Pattern
    Save-WhitelistPatterns -Patterns $patterns

    Write-MoleSuccess "Added to whitelist: $Pattern"
}

function Remove-WhitelistPattern {
    <#
    .SYNOPSIS
        Removes a pattern from the whitelist.
    .PARAMETER Pattern
        The pattern to remove.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $patterns = Get-WhitelistPatterns
    $newPatterns = $patterns | Where-Object { $_ -ne $Pattern }

    if ($newPatterns.Count -eq $patterns.Count) {
        Write-MoleWarning "Pattern not found in whitelist: $Pattern"
        return
    }

    Save-WhitelistPatterns -Patterns $newPatterns
    Write-MoleSuccess "Removed from whitelist: $Pattern"
}

function Test-PatternWhitelisted {
    <#
    .SYNOPSIS
        Checks if a pattern is in the whitelist.
    .PARAMETER Pattern
        The pattern to check.
    .OUTPUTS
        Boolean indicating if pattern is whitelisted.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    $patterns = Get-WhitelistPatterns
    return $patterns -contains $Pattern
}

# ============================================================================
# Interactive Whitelist Management
# ============================================================================

function Show-WhitelistManager {
    <#
    .SYNOPSIS
        Interactive whitelist management UI.
    #>
    Write-MoleBanner

    Write-Host ""
    Write-Host "$($script:PURPLE_BOLD)Whitelist Manager$($script:NC)"
    Write-Host "$($script:GRAY)Select items to protect from cleanup$($script:NC)"
    Write-Host ""

    # Load current whitelist
    $currentPatterns = Get-WhitelistPatterns

    # Get all cache items
    $cacheItems = Get-AllCacheItems

    # Build selection list
    $options = $cacheItems | ForEach-Object { $_.DisplayName }

    # Determine pre-selected items
    $preSelected = @()
    for ($i = 0; $i -lt $cacheItems.Count; $i++) {
        $pattern = $cacheItems[$i].Pattern
        if ($currentPatterns -contains $pattern) {
            $preSelected += $i
        }
    }

    # Multi-select
    $selected = Read-MoleMultiSelect -Message "Select items to PROTECT (these will NOT be cleaned):" -Options $options -PreSelected $preSelected

    # Build new pattern list
    $newPatterns = @()

    foreach ($idx in $selected) {
        $pattern = $cacheItems[$idx].Pattern
        $newPatterns += $pattern
    }

    # Add any custom patterns that weren't in the predefined list
    $predefinedPatterns = $cacheItems | ForEach-Object { $_.Pattern }
    foreach ($pattern in $currentPatterns) {
        if ($predefinedPatterns -notcontains $pattern) {
            $newPatterns += $pattern
        }
    }

    # Save
    Save-WhitelistPatterns -Patterns $newPatterns

    Write-Host ""
    Write-MoleDivider -Char '-' -Width 50
    Write-Host "Whitelist updated with $($newPatterns.Count) protected pattern(s)"
    Write-Host "$($script:GRAY)Config: $($script:WHITELIST_FILE)$($script:NC)"
}

function Show-Whitelist {
    <#
    .SYNOPSIS
        Displays the current whitelist.
    #>
    Write-Host ""
    Write-Host "$($script:PURPLE_BOLD)Current Whitelist$($script:NC)"
    Write-MoleDivider -Char '-' -Width 50

    $patterns = Get-WhitelistPatterns

    if ($patterns.Count -eq 0) {
        Write-Host "$($script:GRAY)No patterns in whitelist$($script:NC)"
        return
    }

    $index = 1
    foreach ($pattern in $patterns) {
        # Determine if it's a default or custom pattern
        $isDefault = $script:DEFAULT_WHITELIST_PATTERNS -contains $pattern
        $marker = if ($isDefault) { "$($script:GRAY)(default)$($script:NC)" } else { "" }

        Write-Host "  $index. $pattern $marker"
        $index++
    }

    Write-MoleDivider -Char '-' -Width 50
    Write-Host "Config file: $($script:GRAY)$($script:WHITELIST_FILE)$($script:NC)"
}

function Reset-Whitelist {
    <#
    .SYNOPSIS
        Resets the whitelist to default patterns.
    #>
    $confirm = Read-MoleConfirmation -Message "Reset whitelist to defaults?" -Default $false

    if ($confirm) {
        Save-WhitelistPatterns -Patterns $script:DEFAULT_WHITELIST_PATTERNS
        Write-MoleSuccess "Whitelist reset to defaults"
    }
    else {
        Write-Host "Reset cancelled."
    }
}

# ============================================================================
# Whitelist Integration
# ============================================================================

function Initialize-Whitelist {
    <#
    .SYNOPSIS
        Initializes the whitelist for cleanup operations.
    .DESCRIPTION
        Loads whitelist patterns and sets them in the FileOps module.
    #>
    $patterns = Get-WhitelistPatterns
    Set-WhitelistPatterns -Patterns $patterns

    Write-MoleDebug "Initialized whitelist with $($patterns.Count) patterns"
}

function Get-WhitelistStats {
    <#
    .SYNOPSIS
        Gets statistics about the whitelist.
    .OUTPUTS
        Hashtable with Total, Default, and Custom counts.
    #>
    $patterns = Get-WhitelistPatterns

    $defaultCount = 0
    $customCount = 0

    foreach ($pattern in $patterns) {
        if ($script:DEFAULT_WHITELIST_PATTERNS -contains $pattern) {
            $defaultCount++
        }
        else {
            $customCount++
        }
    }

    return @{
        Total = $patterns.Count
        Default = $defaultCount
        Custom = $customCount
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Get-AllCacheItems'
    'Get-WhitelistPatterns'
    'Save-WhitelistPatterns'
    'Add-WhitelistPattern'
    'Remove-WhitelistPattern'
    'Test-PatternWhitelisted'
    'Show-WhitelistManager'
    'Show-Whitelist'
    'Reset-Whitelist'
    'Initialize-Whitelist'
    'Get-WhitelistStats'
)
