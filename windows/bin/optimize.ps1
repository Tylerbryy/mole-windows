#!/usr/bin/env pwsh
# Mole Windows - Cache Rebuild + Service Refresh
# Wrapper for mole.ps1 optimize command

#Requires -Version 5.1

$moleScript = Join-Path $PSScriptRoot "..\mole.ps1"
& $moleScript optimize @args
