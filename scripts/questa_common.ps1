Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-VerificationPaths {
    # PSScriptRoot points to the scripts directory regardless of the caller's location.
    $rootDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
    $questaDirectory = Join-Path $rootDirectory "sim\questa"

    [pscustomobject]@{
        Root       = $rootDirectory
        Questa     = $questaDirectory
        Libraries  = Join-Path $questaDirectory "libraries"
        Library    = Join-Path $questaDirectory "libraries\uart_work"
        Runs       = Join-Path $questaDirectory "runs"
        ModelsimIni = Join-Path $questaDirectory "modelsim.ini"
        Projects   = Join-Path $PSScriptRoot "projects.psd1"
    }
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    # Out-Host keeps tool output visible without adding it to the function return value.
    & $Command @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE."
    }
}

function Assert-QuestaTools {
    foreach ($tool in @("vlib", "vmap", "vlog", "vsim")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required Questa command '$tool' was not found in PATH."
        }
    }
}

function Get-ProjectDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Project
    )

    $paths = Get-VerificationPaths
    if (-not (Test-Path -LiteralPath $paths.Projects -PathType Leaf)) {
        throw "Project configuration was not found: $($paths.Projects)"
    }

    $projects = Import-PowerShellDataFile -LiteralPath $paths.Projects
    if (-not $projects.ContainsKey($Project)) {
        $knownProjects = ($projects.Keys | Sort-Object) -join ", "
        throw "Unknown project '$Project'. Configured projects: $knownProjects"
    }

    $definition = $projects[$Project]
    [pscustomobject]@{
        Name     = $Project
        FileList = Join-Path $paths.Root $definition.FileList
        Top      = [string]$definition.Top
        IsUvm    = [bool]$definition.IsUvm
    }
}

function Initialize-QuestaEnvironment {
    $paths = Get-VerificationPaths
    Assert-QuestaTools

    New-Item -ItemType Directory -Path $paths.Questa -Force | Out-Null
    New-Item -ItemType Directory -Path $paths.Libraries -Force | Out-Null
    New-Item -ItemType Directory -Path $paths.Runs -Force | Out-Null

    # Create a project-local modelsim.ini so library mappings stay in this repository.
    if (-not (Test-Path -LiteralPath $paths.ModelsimIni -PathType Leaf)) {
        Push-Location $paths.Questa
        try {
            Invoke-CheckedCommand -Command "vmap" -Arguments @("-c")
        }
        finally {
            Pop-Location
        }
    }

    # A valid Questa library contains an _info metadata file.
    $libraryInfo = Join-Path $paths.Library "_info"
    if (-not (Test-Path -LiteralPath $libraryInfo -PathType Leaf)) {
        Invoke-CheckedCommand -Command "vlib" -Arguments @($paths.Library)
    }

    Invoke-CheckedCommand -Command "vmap" -Arguments @(
        "-modelsimini", $paths.ModelsimIni,
        "uart_work", $paths.Library
    )

    return $paths
}
