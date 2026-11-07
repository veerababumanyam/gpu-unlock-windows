@echo off
setlocal
cd /d "%~dp0"
rem The wizard self-elevates and shows a Next/Next Windows-style setup UI.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\SetupWizard.ps1"
