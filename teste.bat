@echo off
cls

echo #####################################################################
echo #                                                                   #
echo #           Sistema de Coleta de Inventario de TI                   #
echo #                                                                   #
echo # Empresa: DepMSMRJ                                                 #
echo # Autor: 1SG-PL BRUNO                                               #
echo # Contato: bruno.ramos@marinha.mil.br                               #
echo #                                                                   #
echo #####################################################################
echo.
echo Este script ira coletar os dados de inventario do seu computador.
echo.
echo Esta janela sera fechada automaticamente em aguns segundos...
echo.

powershell.exe -ExecutionPolicy Bypass -File ".\teste.ps1"


pause
