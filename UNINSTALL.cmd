@echo off
setlocal
cd /d "%~dp0"
rem The wizard self-elevates and removes the app, settings, task and shortcuts.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0app\UninstallWizard.ps1"
