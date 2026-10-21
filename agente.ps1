# ================================
# Agente Parque 3.3 - Cliente
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
    PERMITIR_CAMINHOS   = ''
    TEMPO_MAX_COMANDO_SEG = 600
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
$statusPath     = Join-Path $cfg.RETORNO_DIR "$pcName.json"
$inventarioPS   = $cfg.COLETOR_WINDOWS
$inventarioHtml = $cfg.HTML_FILE

# Timeout máximo por comando (s) e allowlist de caminhos (separados por ;)
$tempoMax = 600
try { if ([int]$cfg.TEMPO_MAX_COMANDO_SEG -gt 0) { $tempoMax = [int]$cfg.TEMPO_MAX_COMANDO_SEG } } catch {}
$allowlist = @()
if (-not [string]::IsNullOrWhiteSpace($cfg.PERMITIR_CAMINHOS)) {
    $allowlist = @($cfg.PERMITIR_CAMINHOS -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
$avisoAllowlistVazio = $false

# Garantir que pastas existam
foreach ($p in @($executados, (Split-Path $retornoPath))) {
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
}

Write-Host "Agente iniciado para $pcName. Monitorando $comandoPath ..."

# Guarda anti poison-file: JSON inválido não pode travar a fila do host
$falhasParse = 0
$maxFalhasParse = 3

function Get-PowerShellLauncher {
    foreach ($cand in @('powershell.exe', 'pwsh.exe', 'pwsh', 'powershell')) {
        try { return (Get-Command $cand -ErrorAction Stop).Source } catch {}
    }
    return $null
}

function Test-CaminhoPermitido($caminho) {
    if ($allowlist.Count -eq 0) {
        if (-not $script:avisoAllowlistVazio) {
            $script:avisoAllowlistVazio = $true
            Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] AVISO: PERMITIR_CAMINHOS vazio — qualquer caminho é aceito. Restrinja no parque.conf."
        }
        return $true
    }
    try { $alvo = [System.IO.Path]::GetFullPath($caminho).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) }
    catch { return $false }
    foreach ($base in $allowlist) {
        try { $b = [System.IO.Path]::GetFullPath($base).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) }
        catch { continue }
        if ($alvo.Equals($b, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($alvo.StartsWith($b + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($alvo.StartsWith($b + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Invoke-ProcessoSupervisionado($file, $argList, $timeoutSeg, $baseLog) {
    $outLog = "$baseLog.out.log"
    $errLog = "$baseLog.err.log"
    $p = Start-Process -FilePath $file -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog -ErrorAction Stop
    if ($p.WaitForExit($timeoutSeg * 1000)) {
        return [PSCustomObject]@{ ExitCode = $p.ExitCode; Timeout = $false; OutLog = $outLog; ErrLog = $errLog }
    }
    try { $p.Kill() } catch {}
    return [PSCustomObject]@{ ExitCode = $null; Timeout = $true; OutLog = $outLog; ErrLog = $errLog }
}

function Resolve-Desinstalacao($alvo, $params) {
    $alvo = "$alvo".Trim()
    if ($alvo -match '^\{[0-9A-Fa-f-]{36}\}$') {
        return @{ File = 'msiexec.exe'; Args = "/x $alvo /qn $params"; ChecarAllow = $false; Desc = "ProductCode $alvo" }
    }
    if ($alvo.EndsWith('.msi', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{ File = 'msiexec.exe'; Args = "/x `"$alvo`" /qn $params"; ChecarAllow = $true; Alvo = $alvo; Desc = "MSI $alvo" }
    }
    if ($alvo.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @{ File = $alvo; Args = "$params"; ChecarAllow = $true; Alvo = $alvo; Desc = "EXE $alvo" }
    }
    # DisplayName: busca no registro de desinstalação (só Windows)
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    try { $apps = Get-ItemProperty -Path $chaves -ErrorAction Stop | Where-Object { $_.DisplayName -eq $alvo } }
    catch { throw "Busca por nome de produto exige Windows com registro acessível: $($_.Exception.Message)" }
    if (-not $apps) { throw "Produto não encontrado no registro de desinstalação: '$alvo'. Use ProductCode {GUID}, caminho .msi/.exe ou o DisplayName exato." }
    $app = @($apps)[0]
    if ($app.QuietUninstallString) {
        return @{ File = 'cmd.exe'; Args = "/c $($app.QuietUninstallString) $params"; ChecarAllow = $false; Desc = "QuietUninstall de '$alvo'" }
    }
    $us = "$($app.UninstallString)"
    if ($us -match '(?i)msiexec(\.exe)?\s+/I\s*(\{[0-9A-Fa-f-]{36}\})') {
        return @{ File = 'msiexec.exe'; Args = "/x $($Matches[2]) /qn $params"; ChecarAllow = $false; Desc = "ProductCode $($Matches[2]) de '$alvo'" }
    }
    if ($us -match '(?i)\.exe\b') {
        $exe = ($us -replace '(?i)^\s*"([^"]+\.exe)".*', '$1')
        if ($exe -eq $us) { $exe = ($us -split '\s+', 2)[0].Trim('"') }
        return @{ File = $exe; Args = "$params"; ChecarAllow = $true; Alvo = $exe; Desc = "Uninstall de '$alvo'" }
    }
    throw "String de desinstalação sem formato suportado para '$alvo': $us"
}

function Write-StatusAgente($acao, $inicio, $fim, $sucesso, $codigo, $mensagem, $origem, $arquivado) {
    $st = [ordered]@{
        Computador       = $pcName
        Acao             = "$acao"
        Inicio           = "$inicio"
        Fim              = "$fim"
        Sucesso          = [bool]$sucesso
        CodigoSaida      = $codigo
        Mensagem         = "$mensagem"
        ComandoOrigem    = "$origem"
        ArquivoArquivado = "$arquivado"
        AgenteVersao     = '3.3'
    }
    ($st | ConvertTo-Json -Depth 5) | Set-Content -Path $statusPath -Encoding UTF8
}

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
                    $msgInv = "JSON inválido arquivado após $falhasParse tentativas. Corrija e publique novamente em comandos/."
                    Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msgInv ($destinoInv)"
                    Write-StatusAgente -acao '(parse)' -inicio (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -fim (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -sucesso $false -codigo $null -mensagem $msgInv -origem $comandoPath -arquivado $destinoInv
                    $falhasParse = 0
                }
            }

            if ($null -ne $comando) {
            # Log de início
            $acaoInicio = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Add-Content $retornoPath "`n[$acaoInicio] Iniciando ação: $($comando.acao)"
            $resOk = $true
            $resCode = $null
            $resMsg = 'ok'

            switch ($comando.acao) {
                "inventario" {
                    try {
                        Add-Content $retornoPath "Executando inventário..."
                        # Localiza interpretador (powershell 5.1 ou pwsh 7+)
                        $launcher = Get-PowerShellLauncher
                        if (-not $launcher) { throw "Nenhum interpretador PowerShell encontrado (powershell/pwsh)." }
                        # Executa o script de inventário
                        & $launcher -NoProfile -ExecutionPolicy Bypass -File $inventarioPS
                        $code = $LASTEXITCODE
                        $resCode = $code
                        if ($code -ne 0) {
                            $resOk = $false
                            $resMsg = "Coleta terminou com código de saída: $code."
                            Add-Content $retornoPath "$resMsg Verifique o coletor ($inventarioPS)."
                        } else {
                            $resMsg = 'Coleta concluída.'
                            Add-Content $retornoPath "$resMsg Rode o consolidador para atualizar o dashboard ($inventarioHtml)."
                        }
                    }
                    catch {
                        $resOk = $false
                        $resMsg = "Erro ao executar inventário: $($_.Exception.Message)"
                        Add-Content $retornoPath $resMsg
                    }
                }
                "instalar" {
                    $alvo = "$($comando.arquivo)"
                    if ([string]::IsNullOrWhiteSpace($alvo)) {
                        $resOk = $false
                        $resMsg = "Campo 'arquivo' ausente no comando instalar."
                        Add-Content $retornoPath $resMsg
                    } elseif (-not (Test-CaminhoPermitido $alvo)) {
                        $resOk = $false
                        $resMsg = "Caminho fora da allowlist (PERMITIR_CAMINHOS): $alvo"
                        Add-Content $retornoPath $resMsg
                    } else {
                    try {
                        Add-Content $retornoPath "Iniciando instalacao de: $alvo com parametros: $($comando.parametros)"
                        $installParams = $comando.parametros
                        if ($null -eq $installParams) {
                            $installParams = ""
                        }

                        $filePath = $alvo
                        $arguments = $installParams

                        # Check if it's an MSI file
                        $msiLogPath = $null
                        if ($alvo.EndsWith(".msi", [System.StringComparison]::OrdinalIgnoreCase)) {
                            # For MSI, /i is for install, /qn for no UI, /L*v for verbose logging
                            $msiLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "$($pcName)_$((Get-Date -Format 'yyyyMMdd_HHmmss')).log"
                            $arguments = "/i `"$alvo`" /qn /L*v `"$msiLogPath`" $arguments" # /i for install, quote the MSI path, /qn for silent, /L*v for verbose logging
                            $filePath = "msiexec.exe" # Call msiexec
                        }

                        $r = Invoke-ProcessoSupervisionado -file $filePath -argList $arguments -timeoutSeg $tempoMax -baseLog (Join-Path $cfg.RETORNO_DIR "$pcName-instalar")
                        $resCode = $r.ExitCode
                        if ($r.Timeout) {
                            $resOk = $false
                            $resMsg = "Instalacao de $alvo excedeu o timeout de ${tempoMax}s e foi interrompida."
                            Add-Content $retornoPath $resMsg
                        } elseif ($resCode -eq 0) {
                            $resMsg = "Instalacao de $alvo concluida com sucesso. Codigo de saida: $resCode"
                            Add-Content $retornoPath $resMsg
                        } else {
                            $resOk = $false
                            $resMsg = "Instalacao de $alvo FALHOU. Codigo de saida: $resCode"
                            Add-Content $retornoPath $resMsg
                            # If MSI, mention the log file
                            if ($msiLogPath) {
                                Add-Content $retornoPath "Verifique o log do MSI em: $msiLogPath"
                            }
                        }
                    }
                    catch {
                        $resOk = $false
                        $resMsg = "Erro durante a instalacao de ${alvo}: $($_.Exception.Message)"
                        Add-Content $retornoPath $resMsg
                    }
                    }
                }
                "copiar" {
                    $org = "$($comando.origem)"
                    $dst = "$($comando.destino)"
                    if ([string]::IsNullOrWhiteSpace($org) -or [string]::IsNullOrWhiteSpace($dst)) {
                        $resOk = $false
                        $resMsg = "Campos 'origem' e/ou 'destino' ausentes no comando copiar."
                        Add-Content $retornoPath $resMsg
                    } elseif (-not (Test-CaminhoPermitido $org)) {
                        $resOk = $false
                        $resMsg = "Origem fora da allowlist (PERMITIR_CAMINHOS): $org"
                        Add-Content $retornoPath $resMsg
                    } elseif (-not (Test-CaminhoPermitido $dst)) {
                        $resOk = $false
                        $resMsg = "Destino fora da allowlist (PERMITIR_CAMINHOS): $dst"
                        Add-Content $retornoPath $resMsg
                    } else {
                    try {
                        if (-not (Test-Path $org)) { throw "Origem não encontrada: $org" }
                        $destDir = Split-Path $dst -Parent
                        if ($destDir -and -not (Test-Path $destDir)) {
                            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                        }
                        if ((Get-Item $org -Force).PSIsContainer) {
                            Copy-Item -Path (Join-Path $org '*') -Destination $dst -Recurse -Force -ErrorAction Stop
                        } else {
                            Copy-Item -Path $org -Destination $dst -Force -ErrorAction Stop
                        }
                        $bytes = 0
                        try { $bytes = (Get-ChildItem $dst -Recurse -Force -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum } catch {}
                        $resMsg = "Copiado ($bytes bytes): $org -> $dst"
                        Add-Content $retornoPath $resMsg
                    }
                    catch {
                        $resOk = $false
                        $resMsg = "Erro na copia ${org} -> ${dst}: $($_.Exception.Message)"
                        Add-Content $retornoPath $resMsg
                    }
                    }
                }
                "desinstalar" {
                    $alvo = "$($comando.arquivo)"
                    $params = "$($comando.parametros)"
                    if ([string]::IsNullOrWhiteSpace($alvo)) {
                        $resOk = $false
                        $resMsg = "Campo 'arquivo' ausente no comando desinstalar (use ProductCode {GUID}, caminho .msi/.exe ou DisplayName exato)."
                        Add-Content $retornoPath $resMsg
                    } else {
                    try {
                        $sol = Resolve-Desinstalacao $alvo $params
                        Add-Content $retornoPath "Iniciando desinstalacao de: $($sol.Desc)"
                        if ($sol.ChecarAllow -and -not (Test-CaminhoPermitido $sol.Alvo)) {
                            throw "Caminho fora da allowlist (PERMITIR_CAMINHOS): $($sol.Alvo)"
                        }
                        $r = Invoke-ProcessoSupervisionado -file $sol.File -argList $sol.Args -timeoutSeg $tempoMax -baseLog (Join-Path $cfg.RETORNO_DIR "$pcName-desinstalar")
                        $resCode = $r.ExitCode
                        if ($r.Timeout) {
                            $resOk = $false
                            $resMsg = "Desinstalacao de $($sol.Desc) excedeu o timeout de ${tempoMax}s e foi interrompida."
                            Add-Content $retornoPath $resMsg
                        } elseif ($resCode -eq 0 -or $resCode -eq 3010) {
                            $resMsg = "Desinstalacao de $($sol.Desc) concluida. Codigo de saida: $resCode"
                            Add-Content $retornoPath $resMsg
                        } else {
                            $resOk = $false
                            $resMsg = "Desinstalacao de $($sol.Desc) FALHOU. Codigo de saida: $resCode"
                            Add-Content $retornoPath $resMsg
                        }
                    }
                    catch {
                        $resOk = $false
                        $resMsg = "Erro durante a desinstalacao de ${alvo}: $($_.Exception.Message)"
                        Add-Content $retornoPath $resMsg
                    }
                    }
                }
                "executar" {
                    $alvo = "$($comando.arquivo)"
                    $params = "$($comando.parametros)"
                    if ([string]::IsNullOrWhiteSpace($alvo)) {
                        $resOk = $false
                        $resMsg = "Campo 'arquivo' ausente no comando executar."
                        Add-Content $retornoPath $resMsg
                    } elseif (-not (Test-CaminhoPermitido $alvo)) {
                        $resOk = $false
                        $resMsg = "Caminho fora da allowlist (PERMITIR_CAMINHOS): $alvo"
                        Add-Content $retornoPath $resMsg
                    } else {
                    try {
                        if (-not (Test-Path $alvo)) { throw "Arquivo não encontrado: $alvo" }
                        $tmo = $tempoMax
                        try { if ([int]$comando.timeout_seg -gt 0) { $tmo = [int]$comando.timeout_seg } } catch {}
                        $ext = [System.IO.Path]::GetExtension($alvo).ToLowerInvariant()
                        if ($ext -eq '.ps1') {
                            $launcher = Get-PowerShellLauncher
                            if (-not $launcher) { throw "Nenhum interpretador PowerShell encontrado (powershell/pwsh)." }
                            $runFile = $launcher
                            $runArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$alvo`" $params"
                        } elseif ($ext -eq '.bat' -or $ext -eq '.cmd') {
                            $runFile = 'cmd.exe'
                            $runArgs = "/c `"$alvo`" $params"
                        } else {
                            $runFile = $alvo
                            $runArgs = $params
                        }
                        Add-Content $retornoPath "Executando: $alvo $params (timeout ${tmo}s)"
                        $r = Invoke-ProcessoSupervisionado -file $runFile -argList $runArgs -timeoutSeg $tmo -baseLog (Join-Path $cfg.RETORNO_DIR "$pcName-executar")
                        $resCode = $r.ExitCode
                        if ($r.Timeout) {
                            $resOk = $false
                            $resMsg = "Execucao de $alvo excedeu o timeout de ${tmo}s e foi interrompida. Saída em: $($r.OutLog)"
                            Add-Content $retornoPath $resMsg
                        } elseif ($resCode -eq 0) {
                            $resMsg = "Execucao de $alvo concluida. Saída em: $($r.OutLog)"
                            Add-Content $retornoPath $resMsg
                        } else {
                            $resOk = $false
                            $resMsg = "Execucao de $alvo FALHOU. Codigo de saida: $resCode. Saída em: $($r.OutLog)"
                            Add-Content $retornoPath $resMsg
                        }
                    }
                    catch {
                        $resOk = $false
                        $resMsg = "Erro durante a execucao de ${alvo}: $($_.Exception.Message)"
                        Add-Content $retornoPath $resMsg
                    }
                    }
                }
                default {
                    $resOk = $false
                    $resMsg = "Ação desconhecida: $($comando.acao)"
                    Add-Content $retornoPath $resMsg
                }
            }

            # Move o comando para a pasta "executados" (timestamp preserva histórico)
            $destinoCmd = Join-Path $executados ("$pcName-$(Get-Date -Format 'yyyyMMdd_HHmmss').json")
            Move-Item -Path $comandoPath -Destination $destinoCmd -Force

            $acaoFim = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-StatusAgente -acao "$($comando.acao)" -inicio $acaoInicio -fim $acaoFim -sucesso $resOk -codigo $resCode -mensagem $resMsg -origem $comandoPath -arquivado $destinoCmd
            Add-Content $retornoPath "[$acaoFim] Ação concluída (sucesso: $resOk) e comando arquivado em $destinoCmd.`n"
            } # if ($null -ne $comando)
        }
    }
    catch {
        Add-Content $retornoPath "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Erro: $($_.Exception.Message)"
    }

    # Espera o intervalo configurado antes de checar novamente
    Start-Sleep -Seconds ([int]$cfg.INTERVALO_AGENTE_SEG)
}
