@echo off
REM ============================================================
REM  MangoNazlet installer - double-click this file.
REM
REM  Windows blocks .ps1 scripts by default, so this wrapper runs
REM  the installer with that restriction lifted for this one run
REM  only. Nothing about your system's policy is changed.
REM ============================================================

echo.
echo   Starting the MangoNazlet installer...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-MangoNazlet.ps1" %*

echo.
echo   Press any key to close this window.
pause >nul
