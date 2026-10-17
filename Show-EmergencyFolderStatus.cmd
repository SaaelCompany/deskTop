@echo off
if exist "%~dp0Emergency folder.exe" (
  "%~dp0Emergency folder.exe" -Status
) else (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0EmergencyFolder.ps1" -Status
)
echo.
pause
