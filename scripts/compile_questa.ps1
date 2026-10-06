param(
    [Parameter(Mandatory = $true)]
    [string]$Project
)

. (Join-Path $PSScriptRoot "questa_common.ps1")

try {
    $paths = Initialize-QuestaEnvironment
    $definition = Get-ProjectDefinition -Project $Project

    if (-not (Test-Path -LiteralPath $definition.FileList -PathType Leaf)) {
        throw "File list was not found: $($definition.FileList)"
    }

    # File-list entries are resolved from the repository root.
    Push-Location $paths.Root
    try {
        Invoke-CheckedCommand -Command "vlog" -Arguments @(
            "-modelsimini", $paths.ModelsimIni,
            "-sv",
            "-work", "uart_work",
            "-f", $definition.FileList
        )
    }
    finally {
        Pop-Location
    }

    Write-Host "Compilation passed for project '$Project'."
    Write-Host "Shared library: $($paths.Library)"
}
catch {
    Write-Error $_
    exit 1
}
