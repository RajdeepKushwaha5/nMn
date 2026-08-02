@echo off
REM NmN installer. Double-click this file.
REM Uses powershell.exe (Windows PowerShell 5.1), which ships with Windows.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
echo.
pause
