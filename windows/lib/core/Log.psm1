# Mole Windows - Logging System
# Centralized logging with rotation support

#Requires -Version 5.1

# Import dependencies
$corePath = Join-Path $PSScriptRoot "Base.psm1"
if (-not (Get-Module -Name "Base" -ErrorAction SilentlyContinue)) {
    Import-Module $corePath -Force -DisableNameChecking
}

# Prevent multiple loading
if ($script:MOLE_LOG_LOADED) { return }
$script:MOLE_LOG_LOADED = $true

# ============================================================================
# Logging Configuration
# ============================================================================
$script:LOG_MAX_SIZE = 1MB
$script:MOLE_CONFIG_DIR = Join-Path $env:LOCALAPPDATA "mole"
$script:MOLE_LOG_FILE = Join-Path $script:MOLE_CONFIG_DIR "mole.log"
$script:MOLE_DEBUG_LOG_FILE = Join-Path $script:MOLE_CONFIG_DIR "mole_debug_session.log"

# Ensure log directory exists
if (-not (Test-Path $script:MOLE_CONFIG_DIR)) {
    New-Item -Path $script:MOLE_CONFIG_DIR -ItemType Directory -Force | Out-Null
}

# ============================================================================
# Log Rotation
# ============================================================================

function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Rotates log file if it exceeds maximum size.
    #>
    if ($script:MOLE_LOG_ROTATED) { return }
    $script:MOLE_LOG_ROTATED = $true

    $logFile = $script:MOLE_LOG_FILE
    if ($logFile -and (Test-Path $logFile -ErrorAction SilentlyContinue)) {
        $size = (Get-Item $logFile).Length
        if ($size -gt $script:LOG_MAX_SIZE) {
            $oldLog = "$logFile.old"
            if (Test-Path $oldLog) {
                Remove-Item $oldLog -Force -ErrorAction SilentlyContinue
            }
            Move-Item $logFile $oldLog -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# Logging Functions
# ============================================================================

function Write-MoleLog {
    <#
    .SYNOPSIS
        Writes a message to the log file.
    .PARAMETER Message
        The message to log.
    .PARAMETER Level
        Log level: INFO, SUCCESS, WARNING, ERROR, DEBUG.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Level`: $Message"

    # Append to main log
    try {
        Add-Content -Path $script:MOLE_LOG_FILE -Value $logEntry -ErrorAction SilentlyContinue
    }
    catch { }

    # Also append to debug log if debug mode
    if ($env:MOLE_DEBUG -eq "1") {
        try {
            Add-Content -Path $script:MOLE_DEBUG_LOG_FILE -Value $logEntry -ErrorAction SilentlyContinue
        }
        catch { }
    }
}

function Write-MoleInfo {
    <#
    .SYNOPSIS
        Logs and displays an informational message.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "$($script:BLUE)$Message$($script:NC)"
    Write-MoleLog -Message $Message -Level "INFO"
}

function Write-MoleSuccess {
    <#
    .SYNOPSIS
        Logs and displays a success message.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  $($script:GREEN)$($script:ICON_SUCCESS)$($script:NC) $Message"
    Write-MoleLog -Message $Message -Level "SUCCESS"
}

function Write-MoleWarning {
    <#
    .SYNOPSIS
        Logs and displays a warning message.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "$($script:YELLOW)$Message$($script:NC)"
    Write-MoleLog -Message $Message -Level "WARNING"
}

function Write-MoleError {
    <#
    .SYNOPSIS
        Logs and displays an error message.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "$($script:YELLOW)$($script:ICON_ERROR)$($script:NC) $Message" -ForegroundColor Yellow
    Write-MoleLog -Message $Message -Level "ERROR"
}

function Write-MoleDebug {
    <#
    .SYNOPSIS
        Logs a debug message (only when MOLE_DEBUG=1).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($env:MOLE_DEBUG -eq "1") {
        Write-Host "$($script:GRAY)[DEBUG]$($script:NC) $Message" -ForegroundColor DarkGray
        Write-MoleLog -Message $Message -Level "DEBUG"
    }
}

function Write-MoleDryRun {
    <#
    .SYNOPSIS
        Logs a dry-run action message.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  $($script:YELLOW)$($script:ICON_DRY_RUN)$($script:NC) $Message"
    Write-MoleLog -Message "[DRY RUN] $Message" -Level "INFO"
}

function Write-MoleDebugOperation {
    <#
    .SYNOPSIS
        Logs an operation start in debug mode.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,

        [string]$Description
    )

    if ($env:MOLE_DEBUG -eq "1") {
        Write-Host "$($script:GRAY)[DEBUG] === $OperationName ===$($script:NC)" -ForegroundColor DarkGray
        if ($Description) {
            Write-Host "$($script:GRAY)[DEBUG] $Description$($script:NC)" -ForegroundColor DarkGray
        }

        $logLines = @(
            ""
            "=== $OperationName ==="
        )
        if ($Description) {
            $logLines += "Description: $Description"
        }

        foreach ($line in $logLines) {
            Add-Content -Path $script:MOLE_DEBUG_LOG_FILE -Value $line -ErrorAction SilentlyContinue
        }
    }
}

function Write-MoleDebugFileAction {
    <#
    .SYNOPSIS
        Logs a file action with metadata in debug mode.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$FileSize,

        [int]$FileAgeDays
    )

    if ($env:MOLE_DEBUG -eq "1") {
        $msg = "  - $FilePath"
        if ($FileSize) {
            $msg += " ($FileSize"
            if ($FileAgeDays -gt 0) {
                $msg += ", $FileAgeDays days old"
            }
            $msg += ")"
        }

        Write-Host "$($script:GRAY)[DEBUG] $Action`: $msg$($script:NC)" -ForegroundColor DarkGray
        Add-Content -Path $script:MOLE_DEBUG_LOG_FILE -Value "$Action`: $msg" -ErrorAction SilentlyContinue
    }
}

function Write-MoleSystemInfo {
    <#
    .SYNOPSIS
        Logs system information for debugging.
    #>
    if ($script:MOLE_SYS_INFO_LOGGED) { return }
    $script:MOLE_SYS_INFO_LOGGED = $true

    # Reset debug log for new session
    if (Test-Path $script:MOLE_DEBUG_LOG_FILE) {
        Clear-Content $script:MOLE_DEBUG_LOG_FILE -ErrorAction SilentlyContinue
    }

    $sysInfo = Get-SystemInfo
    $divider = "----------------------------------------------------------------------"

    $logContent = @(
        $divider
        "Mole Debug Session - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $divider
        "User: $($sysInfo.User)"
        "Computer: $($sysInfo.ComputerName)"
        "OS: $($sysInfo.OSVersion) (Build $($sysInfo.OSBuild))"
        "Display Version: $($sysInfo.DisplayVersion)"
        "Architecture: $($sysInfo.Architecture)"
        "Processors: $($sysInfo.ProcessorCount)"
        "PowerShell: $($sysInfo.PowerShellVersion)"
        "Admin: $(if ($sysInfo.IsAdmin) { 'Yes' } else { 'No' })"
        $divider
    )

    foreach ($line in $logContent) {
        Add-Content -Path $script:MOLE_DEBUG_LOG_FILE -Value $line -ErrorAction SilentlyContinue
    }

    Write-Host "$($script:GRAY)[DEBUG] Debug logging enabled. Session log: $($script:MOLE_DEBUG_LOG_FILE)$($script:NC)" -ForegroundColor DarkGray
}

function Write-MoleSummaryBlock {
    <#
    .SYNOPSIS
        Prints a formatted summary block.
    .PARAMETER Heading
        The main heading text.
    .PARAMETER Details
        Array of detail lines to display.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Heading,

        [string[]]$Details = @()
    )

    $divider = "======================================================================"

    Write-Host ""
    Write-Host $divider
    Write-Host "$($script:BLUE)$Heading$($script:NC)"

    foreach ($detail in $Details) {
        if ($detail) {
            Write-Host $detail
        }
    }

    Write-Host $divider

    if ($env:MOLE_DEBUG -eq "1") {
        Write-Host "$($script:GRAY)Debug session log saved to:$($script:NC) $($script:MOLE_DEBUG_LOG_FILE)"
    }
}

# ============================================================================
# Initialize Logging
# ============================================================================

# Perform log rotation on module load
Invoke-LogRotation

# Log system info if debug mode
if ($env:MOLE_DEBUG -eq "1") {
    Write-MoleSystemInfo
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Write-MoleLog'
    'Write-MoleInfo'
    'Write-MoleSuccess'
    'Write-MoleWarning'
    'Write-MoleError'
    'Write-MoleDebug'
    'Write-MoleDryRun'
    'Write-MoleDebugOperation'
    'Write-MoleDebugFileAction'
    'Write-MoleSystemInfo'
    'Write-MoleSummaryBlock'
    'Invoke-LogRotation'
)
