# Caminho do arquivo HTML centralizado que servir√° como banco de dados
# Modifique esta linha para o caminho UNC real para evitar problemas com mapeamento de letras
$arquivoHtml = "Z:\CLTI\parque3.0\inventario_web.html"
$dataHora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "Iniciando coleta de dados para $env:COMPUTERNAME..."

# --- FUN√á√ÉO AUXILIAR PARA REMOVER ACENTOS ---
function Remove-Accents { param([string]$InputString); if ([string]::IsNullOrEmpty($InputString)) { return "" }; return ($InputString.Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{M}') }

# --- Cria um objeto para armazenar os dados ---
$dadosColetados = [PSCustomObject]@{
    Computador = $env:COMPUTERNAME; Usuario = $env:USERNAME; IP = 'Nao encontrado'; MAC = 'Nao encontrado'; Computador_Fabricante = 'Indisponivel'; Computador_Modelo = 'Indisponivel'; Computador_Serial = 'Indisponivel'; Chassis_Tipo = 'Indisponivel'; SO = 'Indisponivel'; Build = ''; Data_Instalacao = ''; Uptime_Horas = '0.0'; Dominio_ou_Grupo = 'Indisponivel';
    Status_Ativacao = 'Desconhecido'; Canal_Licenca = 'Desconhecido'; Chave_Parcial = 'N/A'; Chave_OEM_BIOS = 'Nao Coletado';
    CPU = 'Indisponivel'; Arquitetura = ''; CPU_Cores = 0; CPU_Threads = 0; CPU_Clock_MHz = 0; PlacaMae_Fabricante = 'Indisponivel'; PlacaMae_Modelo = 'Indisponivel'; PlacaMae_Serial = 'Indisponivel'; BIOS_Versao = 'Indisponivel'; BIOS_Data = ''; RAM_GB_Total = 0; Qtd_Pentes = 0; RAM_Detalhes = 'Falha ao ler RAM'; Armazenamento_C_GB = 0; Espaco_Livre_C_GB = 0; Espaco_Livre_C_Perc = 0; Discos_Fisicos = 'Falha ao ler discos'; Volumes = 'Falha ao ler volumes'; Modelo_Disco_Principal = 'Indisponivel'; GPU = 'Indisponivel'; Monitores = 'Falha ao ler monitores'; Resolucao_Tela = 'Indisponivel'; Bateria = 'Indisponivel'; Impressoras = 'Falha ao ler impressoras'; Antivirus = 'Desconhecido'; Antivirus_Status = 'Indisponivel'; Firewall_Ativo = 'Nao'; Usa_WSUS = 'Nao'; Servidor_WSUS = ''; DataHora_Coleta = $dataHora
}

# --- COLETA DE DADOS ---
# (O c√≥digo de coleta de dados permanece o mesmo e foi omitido aqui por brevidade)
try { $dadosColetados.IP = (Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPEnabled } | Select-Object -First 1).IPAddress[0] } catch {}
try { $dadosColetados.MAC = ((Get-WmiObject -Class Win32_NetworkAdapter | Where-Object { $_.NetConnectionStatus -eq 2 } | Select-Object -First 1).MACAddress).Replace(':', '-') } catch {}
try {
    $compSystem = Get-WmiObject -Class Win32_ComputerSystem
    $dadosColetados.Computador_Fabricante = Remove-Accents -InputString $compSystem.Manufacturer
    $dadosColetados.Computador_Modelo = Remove-Accents -InputString $compSystem.Model
    $dadosColetados.Dominio_ou_Grupo = $compSystem.Domain
} catch {}
try { $dadosColetados.Computador_Serial = (Get-WmiObject -Class Win32_BIOS).SerialNumber } catch {}
try {
    $chassisId = (Get-WmiObject -Class Win32_SystemEnclosure).ChassisTypes[0]
    switch ($chassisId) { 3  { $dadosColetados.Chassis_Tipo = "Desktop" }; 4  { $dadosColetados.Chassis_Tipo = "Low Profile Desktop" }; 6  { $dadosColetados.Chassis_Tipo = "Mini Tower" }; 7  { $dadosColetados.Chassis_Tipo = "Tower" }; { @(8, 9, 10, 14, 31, 32) -contains $_ } { $dadosColetados.Chassis_Tipo = "Laptop" }; 13 { $dadosColetados.Chassis_Tipo = "All in One" }; default { $dadosColetados.Chassis_Tipo = "Desconhecido ($chassisId)" } }
} catch {}
try {
    $licInfo = Get-WmiObject -Query "SELECT * FROM SoftwareLicensingProduct WHERE ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus = 1" | Select-Object -First 1
    if ($licInfo) { $dadosColetados.Status_Ativacao = "Ativado"; $dadosColetados.Chave_Parcial = $licInfo.PartialProductKey; if ($licInfo.Description -match "OEM") { $dadosColetados.Canal_Licenca = "OEM" } elseif ($licInfo.Description -match "VOLUME") { $dadosColetados.Canal_Licenca = "Volume" } elseif ($licInfo.Description -match "RETAIL") { $dadosColetados.Canal_Licenca = "Retail" } } else { $dadosColetados.Status_Ativacao = "Nao Ativado" }
} catch { $dadosColetados.Status_Ativacao = "Erro na Coleta" }
try {
    $cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    $dadosColetados.CPU = Remove-Accents -InputString $cpuInfo.Name.Trim(); $dadosColetados.CPU_Cores = $cpuInfo.NumberOfCores; $dadosColetados.CPU_Threads = $cpuInfo.NumberOfLogicalProcessors; $dadosColetados.CPU_Clock_MHz = $cpuInfo.MaxClockSpeed
} catch {}
try {
    $soInfo = Get-WmiObject -Class Win32_OperatingSystem
    $dadosColetados.SO = Remove-Accents -InputString $soInfo.Caption; $dadosColetados.Arquitetura = $soInfo.OSArchitecture; $dadosColetados.Build = $soInfo.BuildNumber; $dadosColetados.Data_Instalacao = ([System.Management.ManagementDateTimeConverter]::ToDateTime($soInfo.InstallDate)).ToString("yyyy-MM-dd"); $uptime = (Get-Date) - ([System.Management.ManagementDateTimeConverter]::ToDateTime($soInfo.LastBootUpTime)); $dadosColetados.Uptime_Horas = [math]::Round($uptime.TotalHours, 1).ToString("F1", [System.Globalization.CultureInfo]::InvariantCulture)
} catch {}
try {
    $placaMaeInfo = Get-WmiObject -Class Win32_BaseBoard | Select-Object -First 1
    $dadosColetados.PlacaMae_Fabricante = Remove-Accents -InputString $placaMaeInfo.Manufacturer; $dadosColetados.PlacaMae_Modelo = Remove-Accents -InputString $placaMaeInfo.Product; $dadosColetados.PlacaMae_Serial = $placaMaeInfo.SerialNumber
} catch {}
try {
    $biosInfo = Get-WmiObject -Class Win32_BIOS | Select-Object -First 1
    $dadosColetados.BIOS_Versao = $biosInfo.SMBIOSBIOSVersion; $dadosColetados.BIOS_Data = ([System.Management.ManagementDateTimeConverter]::ToDateTime($biosInfo.ReleaseDate)).ToString("yyyy-MM-dd")
} catch {}
try {
    $pentes = Get-WmiObject -Class Win32_PhysicalMemory
    if ($pentes) {
        $dadosColetados.RAM_GB_Total = [math]::Round(($pentes | Measure-Object -Property Capacity -Sum).Sum / 1GB); $dadosColetados.Qtd_Pentes = $pentes.Count
        $detalhesFormatados = $pentes | ForEach-Object {
            $memTypeString = switch ($_.SMBIOSMemoryType) {
                20 { "DDR" }; 21 { "DDR2" }; 24 { "DDR3" }; 26 { "DDR4" }; 30 { "DDR5" }; default { "Tipo " + $_.SMBIOSMemoryType }
            }
            "[{0}GB/{1}/{2}MHz/{3}]" -f ([math]::Round($_.Capacity / 1GB)), $memTypeString, $_.Speed, (Remove-Accents -InputString $_.Manufacturer)
        }
        $dadosColetados.RAM_Detalhes = $detalhesFormatados -join "; "
    }
} catch { $dadosColetados.RAM_Detalhes = 'Falha ao ler RAM' }
try {
    $discoC = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
    if ($discoC) { $dadosColetados.Armazenamento_C_GB = [math]::Round($discoC.Size / 1GB); $dadosColetados.Espaco_Livre_C_GB = [math]::Round($discoC.FreeSpace / 1GB); $dadosColetados.Espaco_Livre_C_Perc = [math]::Round(($discoC.FreeSpace / $discoC.Size) * 100) }
} catch {}
try { $dadosColetados.Discos_Fisicos = (Get-PhysicalDisk | ForEach-Object { "$($_.MediaType) - $(Remove-Accents -InputString $_.FriendlyName) ($([math]::Round($_.Size / 1GB))GB)" }) -join " | " } catch { $dadosColetados.Discos_Fisicos = "Acesso negado ou indisponivel" }
try { $dadosColetados.Volumes = (Get-Volume | Where-Object DriveLetter | ForEach-Object { "[{0}: {1}GB livre de {2}GB]" -f $_.DriveLetter, [math]::Round($_.SizeRemaining / 1GB), [math]::Round($_.Size / 1GB) }) -join "; " } catch {}
try { 
    $diskNumber = (Get-Partition -DriveLetter C).DiskNumber
    $dadosColetados.Modelo_Disco_Principal = (Get-Disk -Number $diskNumber).Model
} catch { 
    $dadosColetados.Modelo_Disco_Principal = (Get-WmiObject -Class Win32_DiskDrive | Select-Object -First 1).Model
}
try { $dadosColetados.GPU = Remove-Accents -InputString (Get-WmiObject -Class Win32_VideoController | Select-Object -First 1).Name } catch {}
try {
    $monitores = (Get-WmiObject WmiMonitorID -Namespace root\wmi | ForEach-Object {
        $fabricante = -join ($_.ManufacturerName | ForEach-Object {[char]$_})
        $modelo = -join ($_.UserFriendlyName | ForEach-Object {[char]$_})
        $nomeLimpo = ("$fabricante - $modelo").Trim() -replace "`0"
        (Remove-Accents -InputString $nomeLimpo)
    }) -join "; "
    if ($monitores) { $dadosColetados.Monitores = $monitores } else { $dadosColetados.Monitores = "Nenhum monitor detectado" }
} catch { $dadosColetados.Monitores = "Falha ao ler monitores" }
try {
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $dadosColetados.Resolucao_Tela = "{0}x{1}" -f $bounds.Width, $bounds.Height
} catch {
    $dadosColetados.Resolucao_Tela = 'Indisponivel'
}
try { $bat = Get-WmiObject -Class Win32_Battery; if ($bat) { $dadosColetados.Bateria = "$($bat.EstimatedChargeRemaining)%" } else { $dadosColetados.Bateria = "Desktop/Sem bateria" } } catch {}
try { $impressoras = (Get-Printer | ForEach-Object { Remove-Accents -InputString $_.Name }) -join "; "; if ($impressoras) { $dadosColetados.Impressoras = $impressoras } else { $dadosColetados.Impressoras = "Nenhuma impressora instalada" } } catch {}
try {
    $avProducts = @(); $avProducts += Get-WmiObject -Namespace "root/SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; $avProducts += Get-WmiObject -Namespace "root/SecurityCenter" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; $principalAV = $avProducts | Where-Object { $_.displayName -ne "Windows Defender" } | Select-Object -First 1; if (!$principalAV) { $principalAV = $avProducts | Select-Object -First 1 }; if ($principalAV) { $dadosColetados.Antivirus = Remove-Accents -InputString $principalAV.displayName; if (($principalAV.productState -band 0x1000) -or ($principalAV.productState -band 0x10)) { $dadosColetados.Antivirus_Status = "Ativo" } else { $dadosColetados.Antivirus_Status = "Inativo" } }
} catch {}
try { if (Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $true }) { $dadosColetados.Firewall_Ativo = "Sim" } else { $dadosColetados.Firewall_Ativo = "Nao" } } catch {}
try { $wsusPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"; if (Test-Path $wsusPath) { $wsus = Get-ItemProperty -Path $wsusPath -ErrorAction SilentlyContinue; if ($wsus.WUServer) { $dadosColetados.Usa_WSUS = "Sim"; $dadosColetados.Servidor_WSUS = $wsus.WUServer } } } catch {}


# --- GRAVA√á√ÉO SEGURA NO HTML COM FILE LOCKING E MARCADORES ---

Write-Host "Coleta finalizada. Tentando gravar de forma segura no arquivo: $arquivoHtml"

$startMarker = "//<DATA_START>"
$endMarker = "//<DATA_END>"
$tentativas = 5
$esperaSegundos = 3
$sucesso = $false

if (-not (Test-Path $arquivoHtml)) {
    Write-Error "Arquivo HTML template n√£o encontrado em $arquivoHtml. Crie o arquivo a partir do c√≥digo fornecido."
    return
}

for ($i = 1; $i -le $tentativas; $i++) {
    $fileStream = $null
    try {
        $fileStream = [System.IO.File]::Open($arquivoHtml, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        Write-Host "Bloqueio de arquivo obtido na tentativa $i."
        
        # Usar StreamReader para ler o conte√∫do completo
        $streamReader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
        $htmlContent = $streamReader.ReadToEnd()
        $streamReader.Dispose() # Liberar o leitor

        $startIndex = $htmlContent.IndexOf($startMarker) + $startMarker.Length
        $endIndex = $htmlContent.IndexOf($endMarker, $startIndex)

        if ($startIndex -ge $startMarker.Length -and $endIndex -ge 0) {
            
            $dataBlock = $htmlContent.Substring($startIndex, $endIndex - $startIndex)
            $startIndexJson = $dataBlock.IndexOf('[')
            $endIndexJson = $dataBlock.LastIndexOf(']')
            
            # Inicializa a vari√°vel como uma matriz vazia
            [System.Collections.ArrayList]$dadosAtuais = @()
            
            if ($startIndexJson -ne -1 -and $endIndexJson -ne -1 -and $endIndexJson -gt $startIndexJson) {
                # Extrai apenas o conte√∫do do array JSON
                $jsonString = $dataBlock.Substring($startIndexJson, $endIndexJson - $startIndexJson + 1)
                if ($jsonString.Trim() -ne "[]") {
                    try {
                        # A flag -AsHashtable n√£o √© necess√°ria e pode complicar
                        $dadosConvertidos = $jsonString | ConvertFrom-Json -ErrorAction Stop
                        # CORRE√á√ÉO PRINCIPAL: Garante que o resultado seja sempre um array
                        if ($dadosConvertidos -isnot [array]) {
                            $dadosAtuais.Add($dadosConvertidos) | Out-Null
                        } else {
                            $dadosAtuais.AddRange($dadosConvertidos)
                        }
                    } catch { 
                        Write-Warning "JSON no HTML parece corrompido. Ignorando. Erro: $($_.Exception.Message)" 
                    }
                }
            }

            # Filtra o computador atual da lista
            $dadosFiltrados = @($dadosAtuais | Where-Object { $_.Computador -ne $dadosColetados.Computador })
            
            # Adiciona os novos dados √† lista filtrada
            $novosDados = $dadosFiltrados + $dadosColetados
            
            # Converte a lista final para JSON
            $novoArrayJson = $novosDados | ConvertTo-Json -Depth 10 -Compress
            
            # Remonta o conte√∫do do HTML
            $before = $htmlContent.Substring(0, $startIndex)
            $after = $htmlContent.Substring($endIndex)
            # Garante que o JSON esteja sempre formatado como var inventoryData = [...];
            $novoHtmlContent = $before + "`r`n    var inventoryData = " + $novoArrayJson + ";`r`n    " + $after

            # Reescreve o arquivo
            $fileStream.Seek(0, 'Begin') | Out-Null
            $fileStream.SetLength(0) # Limpa o conte√∫do existente
            $streamWriter = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8)
            $streamWriter.Write($novoHtmlContent)
            $streamWriter.Flush()
            $streamWriter.Close() # Fechar o escritor
            
            Write-Host "Arquivo HTML atualizado com sucesso."
            $sucesso = $true
            break 
        } else {
            Write-Warning "N√£o foi poss√≠vel encontrar os marcadores de dados no arquivo HTML. A grava√ß√£o foi cancelada."
            break
        }
    } catch { 
        Write-Warning "Falha ao acessar o arquivo na tentativa $i. Erro: $($_.Exception.Message)" 
    } finally { 
        if ($fileStream) { $fileStream.Close(); $fileStream.Dispose() } 
    }

    if (-not $sucesso -and $i -lt $tentativas) {
        Write-Warning "Aguardando $esperaSegundos segundos para tentar novamente..."
        Start-Sleep -Seconds $esperaSegundos
    }
}

if (-not $sucesso) { Write-Error "N√ÉO FOI POSS√çVEL GRAVAR NO ARQUIVO HTML ap√≥s $tentativas tentativas." -ErrorAction Stop }

# ============================
# Salvar invent·rio individual
# ============================

try {
    $jsonDestino = "Z:\CLTI\parque3.0\inventario\$($env:COMPUTERNAME).json"

    # Converter os dados coletados para JSON formatado
    $json = $dadosColetados | ConvertTo-Json -Depth 10 -Compress

    # Salvar no arquivo correspondente ‡ m·quina
    # Salvar JSON com codificaÁ„o UTF-8 compatÌvel em PS 5.1 e PS 7
[System.IO.File]::WriteAllText($jsonDestino, $json, [System.Text.Encoding]::UTF8)


    Write-Host "Invent·rio individual salvo em $jsonDestino"
}
catch {
    Write-Warning "Falha ao salvar invent·rio individual: $($_.Exception.Message)"
}

# ============================
# Salvar invent·rio individual em HTML
# ============================

try {
    $htmlDestino = "Z:\CLTI\parque3.0\inventario\$($env:COMPUTERNAME).html"

    # Categorias organizadas
    $secaoUsuario = @{
        "Computador"    = $dadosColetados.Computador
        "Usu·rio"       = $dadosColetados.Usuario
        "DomÌnio/Grupo" = $dadosColetados.Dominio_ou_Grupo
    }

    $secaoRede = @{
        "IP"  = $dadosColetados.IP
        "MAC" = $dadosColetados.MAC
    }

    $secaoSistema = @{
        "Sistema Operacional" = $dadosColetados.SO
        "Build"               = $dadosColetados.Build
        "Arquitetura"         = $dadosColetados.Arquitetura
        "Data de InstalaÁ„o"  = $dadosColetados.Data_Instalacao
        "Uptime (horas)"      = $dadosColetados.Uptime_Horas
        "Status AtivaÁ„o"     = $dadosColetados.Status_Ativacao
        "Canal da LicenÁa"    = $dadosColetados.Canal_Licenca
        "Chave Parcial"       = $dadosColetados.Chave_Parcial
        "Chave OEM BIOS"      = $dadosColetados.Chave_OEM_BIOS
    }

    $secaoHardware = @{
        "Fabricante"         = $dadosColetados.Computador_Fabricante
        "Modelo"             = $dadosColetados.Computador_Modelo
        "Serial"             = $dadosColetados.Computador_Serial
        "Tipo Chassis"       = $dadosColetados.Chassis_Tipo
        "Placa M„e - Fabricante" = $dadosColetados.PlacaMae_Fabricante
        "Placa M„e - Modelo"     = $dadosColetados.PlacaMae_Modelo
        "Placa M„e - Serial"     = $dadosColetados.PlacaMae_Serial
        "BIOS - Vers„o"          = $dadosColetados.BIOS_Versao
        "BIOS - Data"            = $dadosColetados.BIOS_Data
        "CPU"               = $dadosColetados.CPU
        "Cores"             = $dadosColetados.CPU_Cores
        "Threads"           = $dadosColetados.CPU_Threads
        "Clock (MHz)"       = $dadosColetados.CPU_Clock_MHz
        "Arquitetura CPU"   = $dadosColetados.Arquitetura
        "RAM Total (GB)"    = $dadosColetados.RAM_GB_Total
        "Pentes RAM"        = $dadosColetados.Qtd_Pentes
        "Detalhes RAM"      = $dadosColetados.RAM_Detalhes
        "Disco C: (GB)"     = $dadosColetados.Armazenamento_C_GB
        "Livre C: (GB)"     = $dadosColetados.Espaco_Livre_C_GB
        "Livre C: (%)"      = $dadosColetados.Espaco_Livre_C_Perc
        "Disco Principal"   = $dadosColetados.Modelo_Disco_Principal
        "Discos FÌsicos"    = $dadosColetados.Discos_Fisicos
        "Volumes"           = $dadosColetados.Volumes
        "GPU"               = $dadosColetados.GPU
        "Monitores"         = $dadosColetados.Monitores
        "ResoluÁ„o Tela"    = $dadosColetados.Resolucao_Tela
        "Bateria"           = $dadosColetados.Bateria
        "Impressoras"       = $dadosColetados.Impressoras
    }

    $secaoSeguranca = @{
        "AntivÌrus"      = $dadosColetados.Antivirus
        "Status AV"      = $dadosColetados.Antivirus_Status
        "Firewall Ativo" = $dadosColetados.Firewall_Ativo
        "Usa WSUS"       = $dadosColetados.Usa_WSUS
        "Servidor WSUS"  = $dadosColetados.Servidor_WSUS
    }

    # FunÁ„o para gerar HTML de uma seÁ„o
    function GerarSecaoHtml($titulo, $hash) {
        $html = "<h2>$titulo</h2><table>"
        foreach ($k in $hash.Keys) {
            $valor = if ([string]::IsNullOrWhiteSpace($hash[$k])) { "IndisponÌvel" } else { $hash[$k] }
            $html += "<tr><td><b>$k</b></td><td>$valor</td></tr>"
        }
        $html += "</table>"
        return $html
    }

    # Montar conte˙do HTML final
    $htmlContent = @"
<!DOCTYPE html>
<html lang='pt-BR'>
<head>
<meta charset='UTF-8'>
<title>Invent·rio - $($dadosColetados.Computador)</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #f9f9f9; }
h1 { color: #007bff; }
h2 { margin-top: 25px; color: #333; border-bottom: 2px solid #007bff; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
td { padding: 6px; border: 1px solid #ccc; }
td:first-child { width: 250px; background: #f0f0f0; font-weight: bold; }
</style>
</head>
<body>
    <h1>Invent·rio - $($dadosColetados.Computador)</h1>
    <p><i>Gerado em $($dadosColetados.DataHora_Coleta)</i></p>
    $(GerarSecaoHtml "Usu·rio" $secaoUsuario)
    $(GerarSecaoHtml "Rede" $secaoRede)
    $(GerarSecaoHtml "Sistema Operacional" $secaoSistema)
    $(GerarSecaoHtml "Hardware" $secaoHardware)
    $(GerarSecaoHtml "SeguranÁa" $secaoSeguranca)
</body>
</html>
"@

    # Gravar no arquivo HTML
    [System.IO.File]::WriteAllText($htmlDestino, $htmlContent, [System.Text.Encoding]::UTF8)

    Write-Host "RelatÛrio individual salvo em $htmlDestino"
}
catch {
    Write-Warning "Falha ao salvar relatÛrio HTML individual: $($_.Exception.Message)"
}
$dadosColetados | Add-Member -NotePropertyName "RelatorioHTML" -NotePropertyValue ".\inventario\$($env:COMPUTERNAME).html"
