@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set "OCR_EXIT=%ERRORLEVEL%"
echo.
if not "%OCR_EXIT%"=="0" echo Installation failed. Read the error above before trying again.
pause
exit /b %OCR_EXIT%
