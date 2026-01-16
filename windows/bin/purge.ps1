#!/usr/bin/env pwsh
# Mole Windows - Project Artifact Cleanup
# Wrapper for mole.ps1 purge command

#Requires -Version 5.1

$moleScript = Join-Path $PSScriptRoot "..\mole.ps1"
& $moleScript purge @args
