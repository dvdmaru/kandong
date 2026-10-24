@echo off
rem KanDong: download models from Hugging Face into the models folder (resumable, SHA256 checked).
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\download-models.ps1"
echo.
pause
