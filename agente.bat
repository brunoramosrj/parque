@echo off
setlocal

REM Caminho completo para o script PowerShell do agente
set PS_SCRIPT=%~dp0agente.ps1

REM Executa o agente em segundo plano (oculto)
rem powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
powershell.exe -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

endlocal
exit
