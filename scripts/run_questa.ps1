param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    # A unique timestamp preserves results from earlier runs.
    [string]$RunId = (Get-Date -Format "yyyyMMdd_HHmmss_fff")
)

. (Join-Path $PSScriptRoot "questa_common.ps1")

try {
    $paths = Initialize-QuestaEnvironment
    $definition = Get-ProjectDefinition -Project $Project
    $runDirectory = Join-Path $paths.Runs (Join-Path $Project $RunId)
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

    $logFile = Join-Path $runDirectory "sim.log"
    $waveFile = Join-Path $runDirectory "waves.wlf"
    $top = "uart_work.$($definition.Top)"

    # MODELSIM avoids command-line parsing problems when modelsim.ini has spaces in its path.
    $previousModelsim = $env:MODELSIM
    $env:MODELSIM = $paths.ModelsimIni

    # Run from the result directory so Questa-generated files remain project-specific.
    Push-Location $runDirectory
    try {
        Invoke-CheckedCommand -Command "vsim" -Arguments @(
            "-c",
            $top,
            "+UVM_NO_RELNOTES",
            "-l", $logFile,
            "-wlf", $waveFile,
            "-do", "log -r /*; run -all; quit -f"
        )
    }
    finally {
        Pop-Location
        $env:MODELSIM = $previousModelsim
    }

    if ($definition.IsUvm) {
        $logText = Get-Content -LiteralPath $logFile -Raw
        if ($logText -notmatch "UVM_ERROR\s*:\s*0" -or
            $logText -notmatch "UVM_FATAL\s*:\s*0") {
            throw "The UVM report did not finish with zero errors and zero fatals. See $logFile"
        }
    }

    Write-Host "Simulation passed for project '$Project'."
    Write-Host "Run directory: $runDirectory"
}
catch {
    Write-Error $_
    exit 1
}
