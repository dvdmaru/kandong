@echo off
rem KanDong launcher: double-click, or drag a video onto this file.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\launch.ps1" %*
