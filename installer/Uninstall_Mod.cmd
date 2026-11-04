@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage_Mod.ps1" Uninstall
set "result=%errorlevel%"
echo.
pause
exit /b %result%
