@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0OpenCodeSessions.exe" (
    echo OpenCodeSessions.exe is missing. Run Build.ps1 or extract the full package.
    pause
    exit /b 1
)
start "" "%~dp0OpenCodeSessions.exe" %*
exit /b %ERRORLEVEL%
