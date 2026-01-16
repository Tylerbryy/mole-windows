@echo off
REM Mole - Windows System Cleaner
REM Command-line wrapper for mole.ps1

setlocal enabledelayedexpansion

REM Get the directory where this script is located
set "SCRIPT_DIR=%~dp0"

REM Run PowerShell script with all arguments
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%mole.ps1" %*
