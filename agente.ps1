# ================================
# Agente Parque 3.0 - Cliente
# ================================

# Nome do computador
$pcName = $env:COMPUTERNAME

# Caminhos no servidor (P:\ já está mapeado)
$basePath     = "P:\ADMIN\parque3.0"
$comandoPath  = Join-Path $basePath "comandos\$pcName.json"
$executados   = Join-Path $basePath "executados"
$retornoPath  = Join-Path $basePath "retorno\$pcName.log"
$inventarioPS = "W:\CLTI\parque3.0\windows.ps1"   # <-- seu script atual
$inventarioHtml = "W:\CLTI\parque3.0\inventario_web.html"

# Garantir que pastas existam
foreach ($p in @($executados, (Split-Path $retornoPath))) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

Write-Host "Agente iniciado para $pcName. Monitorando $comandoPath ..."

# Loop infinito
while ($true) {
    try {
        if (Test-Path $comandoPath) {
            Write-Host "Comando encontrado para $pcName."

            # Lê o conteúdo do comando
            $comando = Get-Content $comandoPath -Raw | ConvertFrom-Json

            # Log de início
            Add-Content $retornoPath "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iniciando ação: $($comando.acao)"

            switch ($comando.acao) {
                "inventario" {
                    try {
                        Add-Content $retornoPath "Executando inventário..."
                        # Executa o script de inventário
                        powershell.exe -ExecutionPolicy Bypass -File $inventarioPS

                        Add-Content $retornoPath "Inventário concluído. Atualizado em $inventarioHtml"
                    }
                    catch {
                        Add-Content $retornoPath "Erro ao executar inventário: $($_.Exception.Message)"
                    }
                }
                "instalar" {
                    Add-Content $retornoPath "Instalação requisitada: $($comando.arquivo) $($comando.parametros)"
                }
                "copiar" {
                    Add-Content $retornoPath "Cópia requisitada: $($comando.origem) -> $($comando.destino)"
                }
                default {
                    Add-Content $retornoPath "Ação desconhecida: $($comando.acao)"
                }
            }

            # Move o comando para a pasta "executados"
            $destinoCmd = Join-Path $executados (Split-Path $comandoPath -Leaf)
            Move-Item -Path $comandoPath -Destination $destinoCmd -Force

            Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ação concluída e comando arquivado.`n"
        }
    }
    catch {
        Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erro: $($_.Exception.Message)"
    }

    # Espera 60 segundos antes de checar novamente
    Start-Sleep -Seconds 60
}
