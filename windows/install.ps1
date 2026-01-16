#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install Mole - Windows System Cleaner
.DESCRIPTION
    Installs Mole to %LOCALAPPDATA%\Programs\mole and adds it to PATH.
.PARAMETER Uninstall
    Remove Mole from the system.
.PARAMETER Force
    Skip confirmation prompts.
.EXAMPLE
    .\install.ps1
    Install Mole to the default location.
.EXAMPLE
    .\install.ps1 -Uninstall
    Remove Mole from the system.
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Configuration
$INSTALL_DIR = Join-Path $env:LOCALAPPDATA "Programs\mole"
$BIN_DIR = Join-Path $INSTALL_DIR "bin"
$SCRIPT_ROOT = $PSScriptRoot

# Colors
$ESC = [char]27
$GREEN = "$ESC[0;32m"
$BLUE = "$ESC[0;34m"
$YELLOW = "$ESC[0;33m"
$RED = "$ESC[0;31m"
$PURPLE = "$ESC[0;35m"
$NC = "$ESC[0m"

function Write-Logo {
    Write-Host @"
$PURPLE
    __  ___      __
   /  |/  /___  / /__
  / /|_/ / __ \/ / _ \
 / /  / / /_/ / /  __/
/_/  /_/\____/_/\___/
$NC
"@
}

function Test-AdminRequired {
    # Check if we need admin (for system PATH modification)
    # For user PATH, we don't need admin
    return $false
}

function Add-ToPath {
    param(
        [string]$PathToAdd
    )

    # Get current user PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($currentPath -split ";" -contains $PathToAdd) {
        Write-Host "${GREEN}Already in PATH${NC}"
        return
    }

    # Add to user PATH
    $newPath = if ($currentPath) { "$currentPath;$PathToAdd" } else { $PathToAdd }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    # Also update current session
    $env:Path = "$env:Path;$PathToAdd"

    Write-Host "${GREEN}Added to PATH${NC}"
}

function Remove-FromPath {
    param(
        [string]$PathToRemove
    )

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if (-not $currentPath) { return }

    $paths = $currentPath -split ";" | Where-Object { $_ -ne $PathToRemove -and $_ -ne "" }
    $newPath = $paths -join ";"

    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")

    Write-Host "${GREEN}Removed from PATH${NC}"
}

function Install-Mole {
    Write-Logo
    Write-Host "${BLUE}Installing Mole...${NC}"
    Write-Host ""

    # Check if already installed
    if (Test-Path $INSTALL_DIR) {
        if (-not $Force) {
            Write-Host "${YELLOW}Mole is already installed at: $INSTALL_DIR${NC}"
            $response = Read-Host "Reinstall? [y/N]"
            if ($response -notmatch "^[Yy]") {
                Write-Host "Installation cancelled."
                return
            }
        }

        # Remove old installation
        Remove-Item -Path $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create installation directory
    Write-Host "Creating installation directory..."
    New-Item -Path $INSTALL_DIR -ItemType Directory -Force | Out-Null
    New-Item -Path $BIN_DIR -ItemType Directory -Force | Out-Null

    # Copy files
    Write-Host "Copying files..."

    # Main script
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "mole.ps1") -Destination $INSTALL_DIR -Force

    # CMD wrapper
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "mo.cmd") -Destination $INSTALL_DIR -Force

    # Also copy to bin for PATH
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "mo.cmd") -Destination $BIN_DIR -Force

    # Create mole.cmd alias in bin
    $moleCmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\mole.ps1" %*
"@
    Set-Content -Path (Join-Path $BIN_DIR "mole.cmd") -Value $moleCmd

    # Libraries
    $libDir = Join-Path $INSTALL_DIR "lib"
    New-Item -Path $libDir -ItemType Directory -Force | Out-Null

    # Core modules
    $coreDir = Join-Path $libDir "core"
    New-Item -Path $coreDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "lib\core\*.psm1") -Destination $coreDir -Force

    # Clean modules
    $cleanDir = Join-Path $libDir "clean"
    New-Item -Path $cleanDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "lib\clean\*.psm1") -Destination $cleanDir -Force

    # Manage modules
    $manageDir = Join-Path $libDir "manage"
    New-Item -Path $manageDir -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $SCRIPT_ROOT "lib\manage\*.psm1") -Destination $manageDir -Force

    # Config directory
    $configDir = Join-Path $INSTALL_DIR "config"
    if (Test-Path (Join-Path $SCRIPT_ROOT "config")) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $SCRIPT_ROOT "config\*") -Destination $configDir -Force -ErrorAction SilentlyContinue
    }

    # Bin directory (for Go executables)
    if (Test-Path (Join-Path $SCRIPT_ROOT "bin")) {
        Copy-Item -Path (Join-Path $SCRIPT_ROOT "bin\*") -Destination $BIN_DIR -Force -ErrorAction SilentlyContinue
    }

    # Add to PATH
    Write-Host "Adding to PATH..."
    Add-ToPath -PathToAdd $BIN_DIR

    # Create config directory
    $userConfigDir = Join-Path $env:LOCALAPPDATA "mole"
    if (-not (Test-Path $userConfigDir)) {
        New-Item -Path $userConfigDir -ItemType Directory -Force | Out-Null
    }

    Write-Host ""
    Write-Host "${GREEN}Installation complete!${NC}"
    Write-Host ""
    Write-Host "Mole installed to: ${BLUE}$INSTALL_DIR${NC}"
    Write-Host "Config directory:  ${BLUE}$userConfigDir${NC}"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  ${PURPLE}mole clean${NC}          Clean system caches"
    Write-Host "  ${PURPLE}mole clean --dry-run${NC} Preview cleanup"
    Write-Host "  ${PURPLE}mole whitelist${NC}      Manage protected paths"
    Write-Host "  ${PURPLE}mole help${NC}           Show all commands"
    Write-Host ""
    Write-Host "${YELLOW}Note: Restart your terminal to use 'mole' command.${NC}"
}

function Uninstall-Mole {
    Write-Logo
    Write-Host "${BLUE}Uninstalling Mole...${NC}"
    Write-Host ""

    if (-not (Test-Path $INSTALL_DIR)) {
        Write-Host "${YELLOW}Mole is not installed at: $INSTALL_DIR${NC}"
        return
    }

    if (-not $Force) {
        $response = Read-Host "Remove Mole from $INSTALL_DIR? [y/N]"
        if ($response -notmatch "^[Yy]") {
            Write-Host "Uninstall cancelled."
            return
        }
    }

    # Remove from PATH
    Write-Host "Removing from PATH..."
    Remove-FromPath -PathToRemove $BIN_DIR

    # Remove installation directory
    Write-Host "Removing files..."
    Remove-Item -Path $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue

    # Ask about config
    $userConfigDir = Join-Path $env:LOCALAPPDATA "mole"
    if (Test-Path $userConfigDir) {
        $response = Read-Host "Remove config and logs at $userConfigDir? [y/N]"
        if ($response -match "^[Yy]") {
            Remove-Item -Path $userConfigDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "${GREEN}Config removed${NC}"
        }
        else {
            Write-Host "Config preserved at: $userConfigDir"
        }
    }

    Write-Host ""
    Write-Host "${GREEN}Mole has been uninstalled.${NC}"
}

# Main
if ($Uninstall) {
    Uninstall-Mole
}
else {
    Install-Mole
}
