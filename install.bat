@echo off
title DSH image drag fix
echo This will stop DeepSeek Harness, swap app.asar and restart it.
echo Edit kill-and-swap.ps1 first if your DSH path is not D:\HaQiFeiYu
pause
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kill-and-swap.ps1"
pause
