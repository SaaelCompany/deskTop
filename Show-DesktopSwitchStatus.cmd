@echo off
if exist "%~dp0DesktopSwitch.exe" (
  "%~dp0DesktopSwitch.exe" -Status
) else (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0DesktopSwitch.ps1" -Status
)
echo.
pause
