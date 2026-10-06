param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [string]$RunId = (Get-Date -Format "yyyyMMdd_HHmmss_fff")
)

$compileScript = Join-Path $PSScriptRoot "compile_questa.ps1"
$runScript = Join-Path $PSScriptRoot "run_questa.ps1"

# Stop immediately when compilation fails; a stale library must not be simulated.
& $compileScript -Project $Project
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& $runScript -Project $Project -RunId $RunId
exit $LASTEXITCODE
