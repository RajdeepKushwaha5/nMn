@echo off
REM NmN launcher. Starts the tray app with no console window.
REM Windows PowerShell 5.1 is required -- it ships with Windows and has the
REM .NET Framework UI Automation assemblies that PowerShell 7 lacks.
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0NmN.ps1"
