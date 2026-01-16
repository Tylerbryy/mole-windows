# Mole Windows - File Operations
# Safe file and directory manipulation with validation

#Requires -Version 5.1

# Import dependencies
$corePath = Join-Path $PSScriptRoot "Base.psm1"
$logPath = Join-Path $PSScriptRoot "Log.psm1"
$protectionPath = Join-Path $PSScriptRoot "PathProtection.psm1"

Import-Module $corePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
Import-Module $logPath -Force -DisableNameChecking -ErrorAction SilentlyContinue
Import-Module $protectionPath -Force -DisableNameChecking -ErrorAction SilentlyContinue

# Prevent multiple loading
if ($script:MOLE_FILE_OPS_LOADED) { return }
$script:MOLE_FILE_OPS_LOADED = $true

# ============================================================================
# Global State
# ============================================================================
$script:MOLE_DRY_RUN = $false
$script:MOLE_PERMISSION_DENIED_COUNT = 0

function Set-MoleDryRun {
    <#
    .SYNOPSIS
        Sets the dry-run mode.
    .PARAMETER Enabled
        Whether dry-run mode is enabled.
    #>
    param(
        [bool]$Enabled = $true
    )
    $script:MOLE_DRY_RUN = $Enabled
}

function Get-MoleDryRun {
    <#
    .SYNOPSIS
        Gets the current dry-run mode state.
    #>
    return $script:MOLE_DRY_RUN
}

function Get-PermissionDeniedCount {
    <#
    .SYNOPSIS
        Gets the count of permission denied errors.
    #>
    return $script:MOLE_PERMISSION_DENIED_COUNT
}

# ============================================================================
# Path Validation
# ============================================================================

function Test-PathForDeletion {
    <#
    .SYNOPSIS
        Validates a path is safe for deletion using 4-layer protection.
    .DESCRIPTION
        Performs these checks:
        1. Path not empty and is absolute
        2. No path traversal attempts (..)
        3. Not a critical system directory
        4. Not protected application data
    .PARAMETER Path
        The path to validate.
    .OUTPUTS
        Boolean - $true if safe to delete, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Layer 1: Check path is not empty
    if ([string]::IsNullOrWhiteSpace($Path)) {
        Write-MoleError "Path validation failed: empty path"
        return $false
    }

    # Layer 2: Check path is absolute (has drive letter on Windows)
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        Write-MoleError "Path validation failed: path must be absolute: $Path"
        return $false
    }

    # Layer 3: Check for path traversal attempts
    # Only reject .. when it appears as a complete path component
    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    if ($normalizedPath -ne $Path.TrimEnd('\', '/') -and $Path -match '\.\.') {
        # Path was normalized differently and contains .., could be traversal
        $resolved = try { Resolve-Path $Path -ErrorAction Stop } catch { $null }
        if ($null -eq $resolved) {
            Write-MoleError "Path validation failed: path traversal not allowed: $Path"
            return $false
        }
    }

    # Layer 4: Check for dangerous characters (control characters, null bytes)
    if ($Path -match '[\x00-\x1F]') {
        Write-MoleError "Path validation failed: contains control characters: $Path"
        return $false
    }

    # Layer 5: Check if path is critical system path
    if (Test-IsCriticalSystemPath -Path $Path) {
        Write-MoleError "Path validation failed: critical system directory: $Path"
        return $false
    }

    # Layer 6: Check if path is protected (using the protection module)
    if (Test-ShouldProtectPath -Path $Path) {
        Write-MoleDebug "Path validation: protected path skipped: $Path"
        return $false
    }

    # Layer 7: Check whitelist (if loaded)
    if (Test-IsPathWhitelisted -Path $Path) {
        Write-MoleDebug "Path validation: whitelisted path skipped: $Path"
        return $false
    }

    return $true
}

# ============================================================================
# Safe Removal Operations
# ============================================================================

function Remove-MolePath {
    <#
    .SYNOPSIS
        Safe wrapper for removing files/directories with validation.
    .DESCRIPTION
        Validates the path before deletion and respects dry-run mode.
    .PARAMETER Path
        The path to remove.
    .PARAMETER Silent
        Suppress error messages for expected failures.
    .OUTPUTS
        Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Silent
    )

    # Validate path
    if (-not (Test-PathForDeletion -Path $Path)) {
        return $false
    }

    # Check if path exists (with error handling for access denied)
    try {
        if (-not (Test-Path $Path -ErrorAction Stop)) {
            return $true  # Already gone, success
        }
    }
    catch [System.UnauthorizedAccessException] {
        # Access denied - can't even check, skip silently
        Write-MoleDebug "Access denied checking path: $Path"
        return $false
    }
    catch {
        # Other error - skip silently
        return $false
    }

    # Dry-run mode: log but don't delete
    if ($script:MOLE_DRY_RUN) {
        $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
        $fileType = if ($item.PSIsContainer) { "directory" } else { "file" }

        $size = Get-PathSize -Path $Path
        $sizeStr = Format-ByteSize -Bytes $size

        $age = if ($item.LastWriteTime) {
            [int]((Get-Date) - $item.LastWriteTime).TotalDays
        } else { 0 }

        if ($env:MOLE_DEBUG -eq "1") {
            Write-MoleDebugFileAction -Action "[DRY RUN] Would remove ($fileType)" -FilePath $Path -FileSize $sizeStr -FileAgeDays $age
        } else {
            Write-MoleDryRun "$Path ($sizeStr)"
        }

        return $true
    }

    Write-MoleDebug "Removing: $Path"

    # Perform the deletion
    try {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        $errorMessage = $_.Exception.Message

        # Check if it's a permission error
        if ($errorMessage -match "Access.*denied|UnauthorizedAccess|permission") {
            $script:MOLE_PERMISSION_DENIED_COUNT++
            Write-MoleDebug "Permission denied: $Path (may need admin rights)"
        }
        elseif (-not $Silent) {
            Write-MoleError "Failed to remove: $Path - $errorMessage"
        }

        return $false
    }
}

function Remove-MolePathAdmin {
    <#
    .SYNOPSIS
        Safe removal with admin privileges (for system cleanup).
    .DESCRIPTION
        Similar to Remove-MolePath but designed for paths requiring elevation.
        Will not process symlinks for safety.
    .PARAMETER Path
        The path to remove.
    .OUTPUTS
        Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Validate path
    if (-not (Test-PathForDeletion -Path $Path)) {
        Write-MoleError "Path validation failed for admin remove: $Path"
        return $false
    }

    # Check if path exists
    if (-not (Test-Path $Path)) {
        return $true
    }

    # Additional check: reject symlinks for admin operations
    $item = Get-Item $Path -Force -ErrorAction SilentlyContinue
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-MoleError "Refusing to admin remove symlink/junction: $Path"
        return $false
    }

    # Dry-run mode
    if ($script:MOLE_DRY_RUN) {
        $size = Get-PathSize -Path $Path
        $sizeStr = Format-ByteSize -Bytes $size

        if ($env:MOLE_DEBUG -eq "1") {
            Write-MoleDebugFileAction -Action "[DRY RUN] Would remove (admin)" -FilePath $Path -FileSize $sizeStr
        } else {
            Write-MoleDryRun "$Path (admin) ($sizeStr)"
        }
        return $true
    }

    Write-MoleDebug "Removing (admin): $Path"

    try {
        # Use Remove-Item with Force
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-MoleError "Failed to remove (admin): $Path - $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# Safe Find and Delete Operations
# ============================================================================

function Remove-MoleItems {
    <#
    .SYNOPSIS
        Safely find and delete items matching a pattern.
    .DESCRIPTION
        Searches a directory for items matching a pattern and removes them,
        respecting age limits, depth limits, and protection rules.
    .PARAMETER BasePath
        The directory to search in.
    .PARAMETER Pattern
        The file/directory name pattern to match.
    .PARAMETER AgeDays
        Minimum age in days for items to be removed (default: 7).
    .PARAMETER Type
        Type filter: File or Directory (default: File).
    .PARAMETER MaxDepth
        Maximum depth to search (default: 5).
    .OUTPUTS
        Number of items removed.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [int]$AgeDays = 7,

        [ValidateSet("File", "Directory")]
        [string]$Type = "File",

        [int]$MaxDepth = 5
    )

    # Validate base directory exists and is not a symlink
    if (-not (Test-Path $BasePath -PathType Container)) {
        Write-MoleError "Directory does not exist: $BasePath"
        return 0
    }

    $baseItem = Get-Item $BasePath -Force -ErrorAction SilentlyContinue
    if ($baseItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-MoleError "Refusing to search symlinked directory: $BasePath"
        return 0
    }

    Write-MoleDebug "Finding in $BasePath`: $Pattern (age: ${AgeDays}d, type: $Type)"

    $cutoffDate = (Get-Date).AddDays(-$AgeDays)
    $removedCount = 0

    try {
        # Build the search parameters
        $searchParams = @{
            Path = $BasePath
            Recurse = $true
            Depth = $MaxDepth
            Force = $true
            ErrorAction = 'SilentlyContinue'
        }

        if ($Type -eq "File") {
            $searchParams.File = $true
        } else {
            $searchParams.Directory = $true
        }

        # Get matching items
        $items = Get-ChildItem @searchParams |
            Where-Object { $_.Name -like $Pattern } |
            Where-Object { $AgeDays -eq 0 -or $_.LastWriteTime -lt $cutoffDate }

        foreach ($item in $items) {
            # Check protection
            if (Test-ShouldProtectPath -Path $item.FullName) {
                continue
            }

            if (Remove-MolePath -Path $item.FullName -Silent) {
                $removedCount++
            }
        }
    }
    catch {
        Write-MoleDebug "Error searching $BasePath`: $($_.Exception.Message)"
    }

    return $removedCount
}

# ============================================================================
# Size Calculation
# ============================================================================

function Get-MolePathSize {
    <#
    .SYNOPSIS
        Gets the size of a path in bytes.
    .PARAMETER Path
        The path to measure.
    .OUTPUTS
        Size in bytes.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return Get-PathSize -Path $Path
}

function Get-MoleTotalSize {
    <#
    .SYNOPSIS
        Calculates total size for multiple paths.
    .PARAMETER Paths
        Array of paths to measure.
    .OUTPUTS
        Total size in bytes.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )

    $totalBytes = 0

    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (Test-Path $path) {
            $totalBytes += Get-PathSize -Path $path
        }
    }

    return $totalBytes
}

# ============================================================================
# Whitelist Support
# ============================================================================

# Global whitelist patterns (loaded by Whitelist module)
$script:WHITELIST_PATTERNS = @()

function Set-WhitelistPatterns {
    <#
    .SYNOPSIS
        Sets the whitelist patterns for path protection.
    #>
    param(
        [string[]]$Patterns
    )
    $script:WHITELIST_PATTERNS = $Patterns
}

function Test-IsPathWhitelisted {
    <#
    .SYNOPSIS
        Checks if a path matches any whitelist pattern.
    .PARAMETER Path
        The path to check.
    .OUTPUTS
        Boolean indicating if path is whitelisted.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($script:WHITELIST_PATTERNS.Count -eq 0) {
        return $false
    }

    $normalizedPath = $Path.TrimEnd('\', '/')

    foreach ($pattern in $script:WHITELIST_PATTERNS) {
        $normalizedPattern = $pattern.TrimEnd('\', '/')

        # Exact match
        if ($normalizedPath -eq $normalizedPattern) {
            return $true
        }

        # Wildcard match
        if ($normalizedPath -like $normalizedPattern) {
            return $true
        }

        # Check if target is under a whitelisted directory
        if ($normalizedPath.StartsWith("$normalizedPattern\")) {
            return $true
        }

        # Check if target is a parent of a whitelisted path
        if ($normalizedPattern.StartsWith("$normalizedPath\")) {
            return $true
        }
    }

    return $false
}

# ============================================================================
# Safe Clean Helper (for cleanup modules)
# ============================================================================

function Invoke-SafeClean {
    <#
    .SYNOPSIS
        High-level function to safely clean a path with description.
    .PARAMETER Path
        The path or glob pattern to clean.
    .PARAMETER Description
        Human-readable description of what's being cleaned.
    .OUTPUTS
        Size cleaned in bytes.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Description
    )

    Set-MoleActivity

    # Handle glob patterns
    $pathsToClean = @()

    if ($Path -match '\*|\?') {
        # It's a glob pattern
        try {
            $pathsToClean = @(Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
        catch {
            return 0
        }
    }
    else {
        if (Test-Path $Path) {
            $pathsToClean = @($Path)
        }
    }

    if ($pathsToClean.Count -eq 0) {
        return 0
    }

    $totalSize = 0
    $cleanedCount = 0

    foreach ($itemPath in $pathsToClean) {
        # Check protection
        if (Test-ShouldProtectPath -Path $itemPath) {
            continue
        }

        if (Test-IsPathWhitelisted -Path $itemPath) {
            continue
        }

        $itemSize = Get-PathSize -Path $itemPath

        if (Remove-MolePath -Path $itemPath -Silent) {
            $totalSize += $itemSize
            $cleanedCount++
        }
    }

    if ($cleanedCount -gt 0) {
        if ($script:MOLE_DRY_RUN) {
            Write-MoleDryRun "$Description - would clean $(Format-ByteSize -Bytes $totalSize)"
        }
        else {
            Write-MoleSuccess "$Description - cleaned $(Format-ByteSize -Bytes $totalSize)"
        }
    }

    return $totalSize
}

# ============================================================================
# Process Check Helper
# ============================================================================

function Test-ProcessRunning {
    <#
    .SYNOPSIS
        Checks if a process is running by name.
    .PARAMETER ProcessName
        The process name to check (without .exe).
    .OUTPUTS
        Boolean indicating if process is running.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName
    )

    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return $null -ne $processes -and $processes.Count -gt 0
}

function Stop-ProcessSafely {
    <#
    .SYNOPSIS
        Attempts to stop a process gracefully, then forcefully if needed.
    .PARAMETER ProcessName
        The process name to stop.
    .PARAMETER Timeout
        Seconds to wait for graceful termination.
    .OUTPUTS
        Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName,

        [int]$Timeout = 5
    )

    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $processes) {
        return $true  # Not running
    }

    # Try graceful close first
    foreach ($proc in $processes) {
        try {
            $proc.CloseMainWindow() | Out-Null
        }
        catch { }
    }

    # Wait for graceful termination
    Start-Sleep -Seconds $Timeout

    # Check if still running
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if (-not $processes) {
        return $true
    }

    # Force kill
    foreach ($proc in $processes) {
        try {
            $proc.Kill()
        }
        catch { }
    }

    Start-Sleep -Seconds 2

    # Final check
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    return $null -eq $processes
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Set-MoleDryRun'
    'Get-MoleDryRun'
    'Get-PermissionDeniedCount'
    'Test-PathForDeletion'
    'Remove-MolePath'
    'Remove-MolePathAdmin'
    'Remove-MoleItems'
    'Get-MolePathSize'
    'Get-MoleTotalSize'
    'Set-WhitelistPatterns'
    'Test-IsPathWhitelisted'
    'Invoke-SafeClean'
    'Test-ProcessRunning'
    'Stop-ProcessSafely'
)
