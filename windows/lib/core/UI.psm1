# Mole Windows - Terminal UI Helpers
# Progress indicators, spinners, and interactive prompts

#Requires -Version 5.1

# Import dependencies
$corePath = Join-Path $PSScriptRoot "Base.psm1"
Import-Module $corePath -Force -DisableNameChecking -ErrorAction SilentlyContinue

# Prevent multiple loading
if ($script:MOLE_UI_LOADED) { return }
$script:MOLE_UI_LOADED = $true

# ============================================================================
# Spinner Management
# ============================================================================
$script:SPINNER_FRAMES = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
$script:SPINNER_JOB = $null
$script:SPINNER_MESSAGE = ""

function Start-MoleSpinner {
    <#
    .SYNOPSIS
        Starts an animated spinner with a message.
    .PARAMETER Message
        The message to display next to the spinner.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Stop-MoleSpinner

    $script:SPINNER_MESSAGE = $Message

    # For PowerShell 5.1 compatibility, use a simple approach
    # Write the initial message
    Write-Host -NoNewline "  $($script:GRAY)$($script:SPINNER_FRAMES[0])$($script:NC) $Message"
}

function Update-MoleSpinner {
    <#
    .SYNOPSIS
        Updates the spinner animation frame.
    .PARAMETER FrameIndex
        The frame index to display.
    #>
    param(
        [int]$FrameIndex = 0
    )

    if (-not $script:SPINNER_MESSAGE) { return }

    $frame = $script:SPINNER_FRAMES[$FrameIndex % $script:SPINNER_FRAMES.Count]

    # Move cursor back and rewrite
    $lineLength = 2 + 2 + $script:SPINNER_MESSAGE.Length + 10  # padding for ANSI codes
    Write-Host -NoNewline "`r  $($script:GRAY)$frame$($script:NC) $($script:SPINNER_MESSAGE)"
}

function Stop-MoleSpinner {
    <#
    .SYNOPSIS
        Stops the spinner and clears the line.
    #>
    if ($script:SPINNER_MESSAGE) {
        # Clear the line
        Write-Host -NoNewline "`r$(' ' * 80)`r"
        $script:SPINNER_MESSAGE = ""
    }
}

# ============================================================================
# Progress Bar
# ============================================================================

function Write-MoleProgress {
    <#
    .SYNOPSIS
        Displays a progress bar.
    .PARAMETER Activity
        The activity description.
    .PARAMETER Status
        The current status.
    .PARAMETER PercentComplete
        The percentage complete (0-100).
    .PARAMETER CurrentOperation
        The current operation being performed.
    #>
    param(
        [string]$Activity = "Processing",
        [string]$Status = "",
        [int]$PercentComplete = 0,
        [string]$CurrentOperation = ""
    )

    # Use built-in Write-Progress for consistency
    $params = @{
        Activity = $Activity
        Status = $Status
        PercentComplete = [Math]::Min(100, [Math]::Max(0, $PercentComplete))
    }

    if ($CurrentOperation) {
        $params.CurrentOperation = $CurrentOperation
    }

    Write-Progress @params
}

function Complete-MoleProgress {
    <#
    .SYNOPSIS
        Completes and hides the progress bar.
    .PARAMETER Activity
        The activity to complete.
    #>
    param(
        [string]$Activity = "Processing"
    )

    Write-Progress -Activity $Activity -Completed
}

# ============================================================================
# Interactive Prompts
# ============================================================================

function Read-MoleConfirmation {
    <#
    .SYNOPSIS
        Prompts the user for Yes/No confirmation.
    .PARAMETER Message
        The message to display.
    .PARAMETER Default
        The default answer if user just presses Enter.
    .OUTPUTS
        Boolean indicating user's choice.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [bool]$Default = $false
    )

    if (-not (Test-IsInteractive)) {
        return $Default
    }

    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }

    Write-Host "$Message $hint" -NoNewline
    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }

    return $response -match '^[Yy]'
}

function Read-MoleChoice {
    <#
    .SYNOPSIS
        Prompts the user to select from multiple options.
    .PARAMETER Message
        The prompt message.
    .PARAMETER Options
        Array of option strings.
    .PARAMETER DefaultIndex
        Index of the default option (0-based).
    .OUTPUTS
        The index of the selected option.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string[]]$Options,

        [int]$DefaultIndex = 0
    )

    Write-Host ""
    Write-Host $Message
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $DefaultIndex) { "$($script:GREEN)$($script:ICON_ARROW)$($script:NC)" } else { " " }
        Write-Host "  $marker [$($i + 1)] $($Options[$i])"
    }

    Write-Host ""

    if (-not (Test-IsInteractive)) {
        return $DefaultIndex
    }

    $response = Read-Host "Enter choice (1-$($Options.Count))"

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultIndex
    }

    $choice = 0
    if ([int]::TryParse($response, [ref]$choice)) {
        if ($choice -ge 1 -and $choice -le $Options.Count) {
            return $choice - 1
        }
    }

    return $DefaultIndex
}

function Read-MoleMultiSelect {
    <#
    .SYNOPSIS
        Prompts the user to select multiple options.
    .PARAMETER Message
        The prompt message.
    .PARAMETER Options
        Array of option strings.
    .PARAMETER PreSelected
        Array of indices that should be pre-selected.
    .OUTPUTS
        Array of selected indices.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string[]]$Options,

        [int[]]$PreSelected = @()
    )

    $selected = [System.Collections.ArrayList]::new()
    foreach ($idx in $PreSelected) {
        if ($idx -ge 0 -and $idx -lt $Options.Count) {
            $selected.Add($idx) | Out-Null
        }
    }

    Write-Host ""
    Write-Host $Message
    Write-Host "$($script:GRAY)(Enter numbers separated by commas, or 'a' for all, 'n' for none)$($script:NC)"
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($selected -contains $i) {
            "$($script:GREEN)$($script:ICON_SOLID)$($script:NC)"
        } else {
            "$($script:GRAY)$($script:ICON_EMPTY)$($script:NC)"
        }
        Write-Host "  $marker [$($i + 1)] $($Options[$i])"
    }

    Write-Host ""

    if (-not (Test-IsInteractive)) {
        return $selected.ToArray()
    }

    $response = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $selected.ToArray()
    }

    if ($response -eq 'a') {
        return @(0..($Options.Count - 1))
    }

    if ($response -eq 'n') {
        return @()
    }

    # Parse comma-separated numbers
    $newSelected = [System.Collections.ArrayList]::new()
    $parts = $response -split ','

    foreach ($part in $parts) {
        $num = 0
        if ([int]::TryParse($part.Trim(), [ref]$num)) {
            $idx = $num - 1
            if ($idx -ge 0 -and $idx -lt $Options.Count -and $newSelected -notcontains $idx) {
                $newSelected.Add($idx) | Out-Null
            }
        }
    }

    return $newSelected.ToArray()
}

# ============================================================================
# Display Helpers
# ============================================================================

function Write-MoleBanner {
    <#
    .SYNOPSIS
        Displays the Mole banner.
    #>
    $banner = @"
$($script:PURPLE_BOLD)
    __  ___      __
   /  |/  /___  / /__
  / /|_/ / __ \/ / _ \
 / /  / / /_/ / /  __/
/_/  /_/\____/_/\___/
$($script:NC)
$($script:GRAY)Windows System Cleaner$($script:NC)
"@

    Write-Host $banner
}

function Write-MoleDivider {
    <#
    .SYNOPSIS
        Displays a horizontal divider line.
    .PARAMETER Char
        The character to use for the divider.
    .PARAMETER Width
        The width of the divider.
    #>
    param(
        [char]$Char = '=',
        [int]$Width = 70
    )

    Write-Host ($Char.ToString() * $Width)
}

function Write-MoleTable {
    <#
    .SYNOPSIS
        Displays data in a formatted table.
    .PARAMETER Data
        Array of hashtables with the data.
    .PARAMETER Columns
        Array of column names to display.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Data,

        [Parameter(Mandatory)]
        [string[]]$Columns
    )

    if ($Data.Count -eq 0) {
        Write-Host "$($script:GRAY)No data to display$($script:NC)"
        return
    }

    # Calculate column widths
    $widths = @{}
    foreach ($col in $Columns) {
        $widths[$col] = $col.Length
    }

    foreach ($row in $Data) {
        foreach ($col in $Columns) {
            $value = "$($row[$col])"
            if ($value.Length -gt $widths[$col]) {
                $widths[$col] = $value.Length
            }
        }
    }

    # Print header
    $header = ""
    $separator = ""
    foreach ($col in $Columns) {
        $header += "$($script:CYAN)$($col.PadRight($widths[$col]))$($script:NC)  "
        $separator += ("-" * $widths[$col]) + "  "
    }
    Write-Host $header
    Write-Host $separator

    # Print rows
    foreach ($row in $Data) {
        $line = ""
        foreach ($col in $Columns) {
            $value = "$($row[$col])".PadRight($widths[$col])
            $line += "$value  "
        }
        Write-Host $line
    }
}

function Write-MoleKeyValue {
    <#
    .SYNOPSIS
        Displays a key-value pair with formatting.
    .PARAMETER Key
        The key/label.
    .PARAMETER Value
        The value.
    .PARAMETER Indent
        Number of spaces to indent.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value,

        [int]$Indent = 2
    )

    $padding = " " * $Indent
    Write-Host "$padding$($script:GRAY)$Key`:$($script:NC) $Value"
}

function Show-MoleCleanupPreview {
    <#
    .SYNOPSIS
        Shows a preview of items that will be cleaned.
    .PARAMETER Items
        Array of items with Path and Size properties.
    .PARAMETER TotalSize
        Total size in bytes.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Items,

        [long]$TotalSize = 0
    )

    Write-Host ""
    Write-Host "$($script:PURPLE_BOLD)$($script:ICON_ARROW) Cleanup Preview$($script:NC)"
    Write-Host ""

    foreach ($item in $Items) {
        $sizeStr = Format-ByteSize -Bytes $item.Size
        Write-Host "  $($script:ICON_LIST) $($item.Description) - $($script:GREEN)$sizeStr$($script:NC)"
    }

    Write-Host ""
    Write-MoleDivider -Char '-' -Width 50
    Write-Host "  Total: $($script:GREEN)$(Format-ByteSize -Bytes $TotalSize)$($script:NC)"
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Start-MoleSpinner'
    'Update-MoleSpinner'
    'Stop-MoleSpinner'
    'Write-MoleProgress'
    'Complete-MoleProgress'
    'Read-MoleConfirmation'
    'Read-MoleChoice'
    'Read-MoleMultiSelect'
    'Write-MoleBanner'
    'Write-MoleDivider'
    'Write-MoleTable'
    'Write-MoleKeyValue'
    'Show-MoleCleanupPreview'
)
