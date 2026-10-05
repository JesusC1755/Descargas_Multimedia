@echo off
setlocal
echo ====================================================
echo   Media Downloader - Launcher de Empaquetado
echo ====================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows-bundle.ps1" %*
pause
