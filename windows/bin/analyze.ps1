#!/usr/bin/env pwsh
# Mole Windows - Disk Usage Explorer
# Wrapper for Go TUI or fallback disk info

#Requires -Version 5.1

$moleScript = Join-Path $PSScriptRoot "..\mole.ps1"
& $moleScript analyze @args
