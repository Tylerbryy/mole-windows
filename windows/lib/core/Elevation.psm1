# Mole Windows - UAC Elevation Handling
# Handles administrator privilege requests and elevation

#Requires -Version 5.1

# Import dependencies
$corePath = Join-Path $PSScriptRoot "Base.psm1"
$logPath = Join-Path $PSScriptRoot "Log.psm1"

Import-Module $corePath -Force -DisableNameChecking -ErrorAction SilentlyContinue
Import-Module $logPath -Force -DisableNameChecking -ErrorAction SilentlyContinue

# Prevent multiple loading
if ($script:MOLE_ELEVATION_LOADED) { return }
$script:MOLE_ELEVATION_LOADED = $true

# ============================================================================
# Elevation Status
# ============================================================================

function Test-IsElevated {
    <#
    .SYNOPSIS
        Checks if the current process is running with administrator privileges.
    .OUTPUTS
        Boolean indicating admin status.
    #>
    return Test-IsAdmin
}

function Get-ElevationStatus {
    <#
    .SYNOPSIS
        Gets detailed elevation status information.
    .OUTPUTS
        Hashtable with elevation details.
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Check if UAC is enabled
    $uacEnabled = try {
        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $value = (Get-ItemProperty $key -Name EnableLUA -ErrorAction Stop).EnableLUA
        $value -eq 1
    } catch {
        $true  # Assume enabled if we can't check
    }

    return @{
        IsAdmin = $isAdmin
        UACEnabled = $uacEnabled
        UserName = $identity.Name
        Groups = $identity.Groups | ForEach-Object {
            try {
                $_.Translate([Security.Principal.NTAccount]).Value
            } catch { }
        }
    }
}

# ============================================================================
# Elevation Requests
# ============================================================================

function Request-Elevation {
    <#
    .SYNOPSIS
        Restarts the current script with administrator privileges.
    .DESCRIPTION
        Creates a new elevated PowerShell process running the same script.
    .PARAMETER Arguments
        Additional arguments to pass to the elevated script.
    .PARAMETER Wait
        Wait for the elevated process to complete.
    .OUTPUTS
        The elevated process object if Wait is false, otherwise the exit code.
    #>
    param(
        [string[]]$Arguments = @(),

        [switch]$Wait
    )

    if (Test-IsElevated) {
        Write-MoleDebug "Already running as administrator"
        return $null
    }

    # Get the current script path
    $scriptPath = $MyInvocation.PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $script:MyInvocation.PSCommandPath
    }

    if (-not $scriptPath) {
        Write-MoleError "Cannot determine script path for elevation"
        return $null
    }

    # Build the argument list
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    if ($Arguments.Count -gt 0) {
        $argList += $Arguments
    }

    Write-MoleInfo "Requesting administrator privileges..."

    try {
        $startInfo = @{
            FilePath = "powershell.exe"
            ArgumentList = $argList
            Verb = "RunAs"
            PassThru = $true
        }

        if ($Wait) {
            $startInfo.Wait = $true
        }

        $process = Start-Process @startInfo

        if ($Wait -and $process) {
            return $process.ExitCode
        }

        return $process
    }
    catch {
        if ($_.Exception.Message -match "canceled by the user|was cancelled") {
            Write-MoleWarning "Administrator access was declined"
        }
        else {
            Write-MoleError "Failed to elevate: $($_.Exception.Message)"
        }
        return $null
    }
}

function Invoke-Elevated {
    <#
    .SYNOPSIS
        Runs a script block with administrator privileges.
    .DESCRIPTION
        Executes code in an elevated PowerShell process.
    .PARAMETER ScriptBlock
        The code to run with elevation.
    .PARAMETER ArgumentList
        Arguments to pass to the script block.
    .OUTPUTS
        Output from the elevated script block.
    #>
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,

        [object[]]$ArgumentList = @()
    )

    if (Test-IsElevated) {
        # Already elevated, just run it
        return & $ScriptBlock @ArgumentList
    }

    # Serialize the script block and arguments
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($ScriptBlock.ToString())
    )

    $argString = ""
    if ($ArgumentList.Count -gt 0) {
        $argString = ($ArgumentList | ForEach-Object { "`"$_`"" }) -join " "
    }

    try {
        $result = Start-Process -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", `
                "-EncodedCommand", $encodedCommand, $argString `
            -Verb RunAs `
            -Wait `
            -PassThru

        return $result.ExitCode -eq 0
    }
    catch {
        Write-MoleError "Elevated execution failed: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# Admin Task Helpers
# ============================================================================

function Get-AdminRequiredOperations {
    <#
    .SYNOPSIS
        Returns a list of operations that require admin privileges.
    .OUTPUTS
        Array of operation descriptions.
    #>
    return @(
        "Clean Windows Update cache"
        "Clean system temp files"
        "Clean Windows Error Reports (system)"
        "Flush DNS cache"
        "Clean thumbnail cache (system)"
        "Manage system services"
    )
}

function Test-OperationNeedsAdmin {
    <#
    .SYNOPSIS
        Checks if a specific operation requires admin privileges.
    .PARAMETER Operation
        The operation name to check.
    .OUTPUTS
        Boolean indicating if admin is required.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Operation
    )

    $adminOps = Get-AdminRequiredOperations
    return $adminOps -contains $Operation
}

function Show-ElevationPrompt {
    <#
    .SYNOPSIS
        Displays a prompt explaining what requires elevation.
    .PARAMETER Operations
        Array of operations that need elevation.
    .OUTPUTS
        Boolean indicating if user wants to proceed.
    #>
    param(
        [string[]]$Operations
    )

    Write-Host ""
    Write-Host "$($script:YELLOW)$($script:ICON_ADMIN) Administrator privileges required for:$($script:NC)"

    foreach ($op in $Operations) {
        Write-Host "  $($script:ICON_LIST) $op"
    }

    Write-Host ""

    if (-not (Test-IsInteractive)) {
        Write-MoleWarning "Non-interactive mode - skipping admin operations"
        return $false
    }

    $response = Read-Host "Proceed with elevation? [y/N]"
    return $response -match '^[Yy]'
}

# ============================================================================
# Safe Elevated Operations
# ============================================================================

function Invoke-ElevatedCleanup {
    <#
    .SYNOPSIS
        Performs cleanup operations that require elevation.
    .DESCRIPTION
        Bundles multiple admin-required operations into a single elevation request.
    .PARAMETER Operations
        Array of operation names to perform.
    .PARAMETER DryRun
        If true, only preview what would be done.
    .OUTPUTS
        Hashtable with results of each operation.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Operations,

        [switch]$DryRun
    )

    $results = @{}

    # Build the cleanup script
    $cleanupScript = {
        param($ops, $dryRun)

        $results = @{}

        foreach ($op in $ops) {
            try {
                switch ($op) {
                    "windows_update" {
                        $path = "$env:SystemRoot\SoftwareDistribution\Download\*"
                        if ($dryRun) {
                            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                                     Measure-Object -Property Length -Sum).Sum
                            $results[$op] = @{ Success = $true; Size = $size; DryRun = $true }
                        }
                        else {
                            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                            $results[$op] = @{ Success = $true }
                        }
                    }

                    "system_temp" {
                        $path = "$env:SystemRoot\Temp\*"
                        if ($dryRun) {
                            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                                     Measure-Object -Property Length -Sum).Sum
                            $results[$op] = @{ Success = $true; Size = $size; DryRun = $true }
                        }
                        else {
                            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                            $results[$op] = @{ Success = $true }
                        }
                    }

                    "dns_cache" {
                        if (-not $dryRun) {
                            Clear-DnsClientCache -ErrorAction SilentlyContinue
                        }
                        $results[$op] = @{ Success = $true }
                    }

                    "wer_system" {
                        $path = "$env:ProgramData\Microsoft\Windows\WER\*"
                        if ($dryRun) {
                            $size = (Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                                     Measure-Object -Property Length -Sum).Sum
                            $results[$op] = @{ Success = $true; Size = $size; DryRun = $true }
                        }
                        else {
                            Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
                            $results[$op] = @{ Success = $true }
                        }
                    }

                    default {
                        $results[$op] = @{ Success = $false; Error = "Unknown operation" }
                    }
                }
            }
            catch {
                $results[$op] = @{ Success = $false; Error = $_.Exception.Message }
            }
        }

        return $results
    }

    if (Test-IsElevated) {
        # Already admin, run directly
        return & $cleanupScript -ops $Operations -dryRun $DryRun
    }
    else {
        # Need to elevate
        $result = Invoke-Elevated -ScriptBlock $cleanupScript -ArgumentList @($Operations, $DryRun)

        if ($result) {
            return @{ Success = $true }
        }
        else {
            return @{ Success = $false; Error = "Elevation failed or was declined" }
        }
    }
}

# ============================================================================
# Export Module Members
# ============================================================================
Export-ModuleMember -Function @(
    'Test-IsElevated'
    'Get-ElevationStatus'
    'Request-Elevation'
    'Invoke-Elevated'
    'Get-AdminRequiredOperations'
    'Test-OperationNeedsAdmin'
    'Show-ElevationPrompt'
    'Invoke-ElevatedCleanup'
)
