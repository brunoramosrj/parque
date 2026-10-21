# ================================
# Agente Parque 3.2 - Cliente
# ================================

# Nome do computador (COMPUTERNAME no Windows; HOSTNAME/hostname como fallback)
$pcName = $env:COMPUTERNAME
if ([string]::IsNullOrWhiteSpace($pcName)) { $pcName = $env:HOSTNAME }
if ([string]::IsNullOrWhiteSpace($pcName)) {
    try { $pcName = (hostname).Trim() } catch { $pcName = "" }
}
if ([string]::IsNullOrWhiteSpace($pcName)) { throw "Não foi possível determinar o nome do computador (COMPUTERNAME/HOSTNAME)." }

# --- CARREGA CONFIGURACAO (parque.conf) ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$cfg = @{
    PROJECT_DIR         = $scriptDir
    COMANDOS_DIR        = 'comandos'
    EXECUTADOS_DIR      = 'executados'
    RETORNO_DIR         = 'retorno'
    COLETOR_WINDOWS     = 'windows.ps1'
    HTML_FILE           = 'inventario_web.html'
    INTERVALO_AGENTE_SEG = 60
}
$configFile = Join-Path $scriptDir 'parque.conf'
if (Test-Path $configFile) {
    Get-Content $configFile -Encoding UTF8 | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
            $eq = $line.IndexOf('=')
            $k = $line.Substring(0, $eq).Trim()
            $v = $line.Substring($eq + 1).Trim()
            if ($k -and $v) { $cfg[$k] = $v }
        }
    }
}
# Resolve caminhos derivados (relativos a PROJECT_DIR quando nao forem absolutos)
function Resolve-CfgPath($p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $p }
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $cfg.PROJECT_DIR $p)
}
$cfg.COMANDOS_DIR    = Resolve-CfgPath $cfg.COMANDOS_DIR
$cfg.EXECUTADOS_DIR  = Resolve-CfgPath $cfg.EXECUTADOS_DIR
$cfg.RETORNO_DIR     = Resolve-CfgPath $cfg.RETORNO_DIR
$cfg.COLETOR_WINDOWS = Resolve-CfgPath $cfg.COLETOR_WINDOWS
$cfg.HTML_FILE       = Resolve-CfgPath $cfg.HTML_FILE

# Caminhos no servidor (derivados da configuracao)
$comandoPath    = Join-Path $cfg.COMANDOS_DIR "$pcName.json"
$executados     = $cfg.EXECUTADOS_DIR
$retornoPath    = Join-Path $cfg.RETORNO_DIR "$pcName.log"
$inventarioPS   = $cfg.COLETOR_WINDOWS
$inventarioHtml = $cfg.HTML_FILE

# Garantir que pastas existam
foreach ($p in @($executados, (Split-Path $retornoPath))) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

Write-Host "Agente iniciado para $pcName. Monitorando $comandoPath ..."

# Guarda anti poison-file: JSON inválido não pode travar a fila do host
$falhasParse = 0
$maxFalhasParse = 3

# Loop infinito
while ($true) {
    try {
        if (Test-Path $comandoPath) {
            Write-Host "Comando encontrado para $pcName."

            # Lê o conteúdo do comando (parse isolado: erro aqui não despacha nada)
            $comando = $null
            try {
                $comando = Get-Content $comandoPath -Raw | ConvertFrom-Json
                $falhasParse = 0
            } catch {
                $falhasParse++
                if ($falhasParse -eq 1) {
                    Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erro de parse em ${comandoPath}: $($_.Exception.Message)"
                }
                if ($falhasParse -ge $maxFalhasParse) {
                    $destinoInv = Join-Path $executados ("$pcName.invalido-$(Get-Date -Format 'yyyyMMdd_HHmmss').json")
                    Move-Item -Path $comandoPath -Destination $destinoInv -Force
                    Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] JSON inválido arquivado em $destinoInv após $falhasParse tentativas. Corrija e publique novamente em comandos/."
                    $falhasParse = 0
                }
            }

            if ($null -ne $comando) {
            # Log de início
            Add-Content $retornoPath "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iniciando ação: $($comando.acao)"

            switch ($comando.acao) {
                "inventario" {
                    try {
                        Add-Content $retornoPath "Executando inventário..."
                        # Localiza interpretador (powershell 5.1 ou pwsh 7+)
                        $launcher = $null
                        foreach ($cand in @('powershell.exe', 'pwsh.exe', 'pwsh', 'powershell')) {
                            try { $launcher = (Get-Command $cand -ErrorAction Stop).Source; break } catch {}
                        }
                        if (-not $launcher) { throw "Nenhum interpretador PowerShell encontrado (powershell/pwsh)." }
                        # Executa o script de inventário
                        & $launcher -NoProfile -ExecutionPolicy Bypass -File $inventarioPS
                        $code = $LASTEXITCODE
                        if ($code -ne 0) {
                            Add-Content $retornoPath "Coleta terminou com código de saída: $code. Verifique o coletor ($inventarioPS)."
                        } else {
                            Add-Content $retornoPath "Coleta concluída. Rode o consolidador para atualizar o dashboard ($inventarioHtml)."
                        }
                    }
                    catch {
                        Add-Content $retornoPath "Erro ao executar inventário: $($_.Exception.Message)"
                    }
                }
                "instalar" {
                    try {
                        Add-Content $retornoPath "Iniciando instalacao de: $($comando.arquivo) com parametros: $($comando.parametros)"
                        $installParams = $comando.parametros
                        if ($null -eq $installParams) {
                            $installParams = ""
                        }

                        $filePath = $comando.arquivo
                        $arguments = $installParams

                        # Check if it's an MSI file
                        if ($filePath.EndsWith(".msi", [System.StringComparison]::OrdinalIgnoreCase)) {
                            # For MSI, /i is for install, /qn for no UI, /L*v for verbose logging
                            # We should also add a log file for MSI installations to debug further
                            $msiLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($pcName)_$((Get-Date -Format 'yyyyMMdd_HHmmss')).log"
                            $arguments = "/i `"$filePath`" /qn /L*v `"$msiLogPath`" $arguments" # /i for install, quote the MSI path, /qn for silent, /L*v for verbose logging
                            $filePath = "msiexec.exe" # Call msiexec
                        }

                        $process = Start-Process -FilePath $filePath -ArgumentList $arguments -Wait -NoNewWindow -PassThru -ErrorAction Stop
                        $exitCode = $process.ExitCode

                        if ($exitCode -eq 0) {
                            Add-Content $retornoPath "Instalacao de $($comando.arquivo) concluida com sucesso. Codigo de saida: $exitCode"
                        } else {
                            Add-Content $retornoPath "Instalacao de $($comando.arquivo) FALHOU. Codigo de saida: $exitCode"
                            # If MSI, mention the log file
                            if ($filePath -eq "msiexec.exe") {
                                Add-Content $retornoPath "Verifique o log do MSI em: $msiLogPath"
                            }
                        }
                    }
                    catch {
                        Add-Content $retornoPath "Erro durante a instalacao de $($comando.arquivo): $($_.Exception.Message)"
                    }
                }
                "copiar" {
                    Add-Content $retornoPath "Cópia requisitada: $($comando.origem) -> $($comando.destino)"
                }
                default {
                    Add-Content $retornoPath "Ação desconhecida: $($comando.acao)"
                }
            }

            # Move o comando para a pasta "executados" (timestamp preserva histórico)
            $destinoCmd = Join-Path $executados ("$pcName-$(Get-Date -Format 'yyyyMMdd_HHmmss').json")
            Move-Item -Path $comandoPath -Destination $destinoCmd -Force

            Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Ação concluída e comando arquivado em $destinoCmd.`n"
            } # if ($null -ne $comando)
        }
    }
    catch {
        Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erro: $($_.Exception.Message)"
    }

    # Espera o intervalo configurado antes de checar novamente
    Start-Sleep -Seconds ([int]$cfg.INTERVALO_AGENTE_SEG)
}
