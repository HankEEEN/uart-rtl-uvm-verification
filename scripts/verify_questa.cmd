@echo off
REM This wrapper bypasses the local PowerShell execution policy for this process only.
REM Usage: verify_questa.cmd clk_gen

if "%~1"=="" (
    echo Usage: verify_questa.cmd PROJECT
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_questa.ps1" -Project "%~1"
exit /b %ERRORLEVEL%
