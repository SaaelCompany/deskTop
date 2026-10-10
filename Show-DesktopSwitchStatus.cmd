@echo off
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0DesktopSwitch.ps1" -Status
echo.
pause
