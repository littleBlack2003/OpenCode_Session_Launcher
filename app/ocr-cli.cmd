@echo off
setlocal DisableDelayedExpansion
set "OCR_CORE=%~dp0ocr-core.ps1"
if not exist "%OCR_CORE%" set "OCR_CORE=%~dp0ocr_v5.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OCR_CORE%" %*
set "OCR_EXIT=%ERRORLEVEL%"
if not "%OCR_EXIT%"=="0" (
    echo.
    echo OpenCode exited with an error. See the message above.
    pause
)
exit /b %OCR_EXIT%
