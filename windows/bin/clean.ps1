#!/usr/bin/env pwsh
# Mole Windows - Deep Cleanup Orchestrator
# Wrapper for mole.ps1 clean command

#Requires -Version 5.1

$moleScript = Join-Path $PSScriptRoot "..\mole.ps1"
& $moleScript clean @args
