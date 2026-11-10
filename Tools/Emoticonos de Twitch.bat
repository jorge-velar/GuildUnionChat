@echo off
rem Guild Union - emoticonos de un canal de Twitch. Doble clic, con el juego cerrado.
rem No hace falta instalar nada: usa PowerShell, que ya viene con Windows.
title Guild Union - emoticonos de Twitch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0emotes_twitch.ps1"
echo.
pause
