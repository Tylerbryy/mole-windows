#!/usr/bin/env pwsh
# Mole Windows - System Health Dashboard
# Wrapper for Go TUI or fallback system info

#Requires -Version 5.1

$moleScript = Join-Path $PSScriptRoot "..\mole.ps1"
& $moleScript status @args
