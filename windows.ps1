$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
# Caminho do arquivo HTML centralizado que servirá como banco de dados
$arquivoHtml = "P:\ADMIN\parque3.0\inventario_web.html"
$dataHora = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "Iniciando coleta de dados para $env:COMPUTERNAME..."

# --- FUNÇÃO AUXILIAR PARA REMOVER ACENTOS ---
function Remove-Accents { param([string]$InputString); if ([string]::IsNullOrEmpty($InputString)) { return "" }; return ($InputString.Normalize([System.Text.NormalizationForm]::FormD) -replace '\p{M}') }

# --- Cria um objeto para armazenar os dados ---
$dadosColetados = [PSCustomObject]@{
    Computador = $env:COMPUTERNAME; Usuario = $env:USERNAME; IP = 'Nao encontrado'; MAC = 'Nao encontrado'; Computador_Fabricante = 'Indisponivel'; Computador_Modelo = 'Indisponivel'; Computador_Serial = 'Indisponivel'; Chassis_Tipo = 'Indisponivel'; SO = 'Indisponivel'; Build = ''; Data_Instalacao = ''; Uptime_Horas = '0.0'; Uptime_Formatado = 'Indisponivel'; Dominio_ou_Grupo = 'Indisponivel';
    Status_Ativacao = 'Desconhecido'; Canal_Licenca = 'Desconhecido'; Chave_Parcial = 'N/A'; Chave_OEM_BIOS = 'Nao Coletado';
    CPU = 'Indisponivel'; Arquitetura = ''; CPU_Cores = 0; CPU_Threads = 0; CPU_Clock_MHz = 0; PlacaMae_Fabricante = 'Indisponivel'; PlacaMae_Modelo = 'Indisponivel'; PlacaMae_Serial = 'Indisponivel'; BIOS_Versao = 'Indisponivel'; BIOS_Data = ''; RAM_GB_Total = 0; Qtd_Pentes = 0; RAM_Detalhes = 'Falha ao ler RAM'; Armazenamento_C_GB = 0; Espaco_Livre_C_GB = 0; Espaco_Livre_C_Perc = 0; Discos_Fisicos = 'Falha ao ler discos'; Volumes = 'Falha ao ler volumes'; Modelo_Disco_Principal = 'Indisponivel'; GPU = 'Indisponivel'; Monitores = 'Falha ao ler monitores'; Resolucao_Tela = 'Indisponivel'; Bateria = 'Indisponivel'; Impressoras = 'Falha ao ler impressoras'; Antivirus = 'Desconhecido'; Antivirus_Status = 'Indisponivel'; Firewall_Ativo = 'Nao'; Usa_WSUS = 'Nao'; Servidor_WSUS = ''; DataHora_Coleta = $dataHora;
    # Novas coletas
    AdminsLocais = 'Nao Coletado'; UpdatesPendentes = 'Nao Coletado'; UltimaInstalacaoUpdates = 'Nao Coletado'; PortasTCP_Abertas = 'Nao Coletado'; PortasUDP_Abertas = 'Nao Coletado'; SaudeDiscoSMART = 'Nao Coletado'; NumeroSerieMonitores = 'Nao Coletado'; GatewayPadrao = 'Nao Coletado'; ServidoresDNS = 'Nao Coletado'; ServidorDHCP = 'Nao Coletado'; DHCPAtivado = $false; ConsumoCPU_Percentual = 0; ConsumoRAM_Percentual = 0; Top5ProcessosCPU = 'Nao Coletado'; Top5ProcessosRAM = 'Nao Coletado'
}

# --- COLETA DE DADOS OTIMIZADA COM Get-CimInstance ---
Write-Host "Coletando informacoes basicas..."
try {
    $compSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $dadosColetados.Computador_Fabricante = Remove-Accents -InputString $compSystem.Manufacturer
    $dadosColetados.Computador_Modelo = Remove-Accents -InputString $compSystem.Model
    $dadosColetados.Dominio_ou_Grupo = $compSystem.Domain
} catch {}
try { $dadosColetados.Computador_Serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber } catch {}
try {
    $chassisId = (Get-CimInstance -ClassName Win32_SystemEnclosure).ChassisTypes[0]
    switch ($chassisId) { 3  { $dadosColetados.Chassis_Tipo = "Desktop" }; 4  { $dadosColetados.Chassis_Tipo = "Low Profile Desktop" }; 6  { $dadosColetados.Chassis_Tipo = "Mini Tower" }; 7  { $dadosColetados.Chassis_Tipo = "Tower" }; { @(8, 9, 10, 14, 31, 32) -contains $_ } { $dadosColetados.Chassis_Tipo = "Laptop" }; 13 { $dadosColetados.Chassis_Tipo = "All in One" }; default { $dadosColetados.Chassis_Tipo = "Desconhecido ($chassisId)" } }
} catch {}

Write-Host "Coletando informacoes de SO e licenca..."
try {
    $licInfo = Get-CimInstance -Query "SELECT PartialProductKey, Description, LicenseStatus FROM SoftwareLicensingProduct WHERE ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus = 1" | Select-Object -First 1
    if ($licInfo) { $dadosColetados.Status_Ativacao = "Ativado"; $dadosColetados.Chave_Parcial = $licInfo.PartialProductKey; if ($licInfo.Description -match "OEM") { $dadosColetados.Canal_Licenca = "OEM" } elseif ($licInfo.Description -match "VOLUME") { $dadosColetados.Canal_Licenca = "Volume" } elseif ($licInfo.Description -match "RETAIL") { $dadosColetados.Canal_Licenca = "Retail" } } else { $dadosColetados.Status_Ativacao = "Nao Ativado" }
} catch { $dadosColetados.Status_Ativacao = "Erro na Coleta" }
try {
    $soInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    $dadosColetados.SO = Remove-Accents -InputString $soInfo.Caption; $dadosColetados.Arquitetura = $soInfo.OSArchitecture; $dadosColetados.Build = $soInfo.BuildNumber; $dadosColetados.Data_Instalacao = $soInfo.InstallDate.ToString("yyyy-MM-dd")
    $uptime = (Get-Date) - $soInfo.LastBootUpTime
    $dadosColetados.Uptime_Horas = [math]::Round($uptime.TotalHours, 1).ToString("F1", [System.Globalization.CultureInfo]::InvariantCulture)
    $dadosColetados.Uptime_Formatado = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
} catch {}

Write-Host "Coletando informacoes de hardware (CPU, Placa-mae, BIOS, RAM)..."
try {
    $cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
    $dadosColetados.CPU = Remove-Accents -InputString $cpuInfo.Name.Trim(); $dadosColetados.CPU_Cores = $cpuInfo.NumberOfCores; $dadosColetados.CPU_Threads = $cpuInfo.NumberOfLogicalProcessors; $dadosColetados.CPU_Clock_MHz = $cpuInfo.MaxClockSpeed
} catch {}
try {
    $placaMaeInfo = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -First 1
    $dadosColetados.PlacaMae_Fabricante = Remove-Accents -InputString $placaMaeInfo.Manufacturer; $dadosColetados.PlacaMae_Modelo = Remove-Accents -InputString $placaMaeInfo.Product; $dadosColetados.PlacaMae_Serial = $placaMaeInfo.SerialNumber
} catch {}
try {
    $biosInfo = Get-CimInstance -ClassName Win32_BIOS | Select-Object -First 1
    $dadosColetados.BIOS_Versao = $biosInfo.SMBIOSBIOSVersion; $dadosColetados.BIOS_Data = ([System.Management.ManagementDateTimeConverter]::ToDateTime($biosInfo.ReleaseDate)).ToString("yyyy-MM-dd")
} catch {}
try {
    $pentes = Get-CimInstance -ClassName Win32_PhysicalMemory
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

Write-Host "Coletando informacoes de armazenamento..."
try {
    $discoC = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    if ($discoC) { $dadosColetados.Armazenamento_C_GB = [math]::Round($discoC.Size / 1GB); $dadosColetados.Espaco_Livre_C_GB = [math]::Round($discoC.FreeSpace / 1GB); $dadosColetados.Espaco_Livre_C_Perc = [math]::Round(($discoC.FreeSpace / $discoC.Size) * 100) }
} catch {}
try { $dadosColetados.Discos_Fisicos = (Get-PhysicalDisk | ForEach-Object { "$($_.MediaType) - $(Remove-Accents -InputString $_.FriendlyName) ($([math]::Round($_.Size / 1GB))GB)" }) -join " | " } catch { $dadosColetados.Discos_Fisicos = "Acesso negado ou indisponivel" }
try { $dadosColetados.Volumes = (Get-Volume | Where-Object DriveLetter | ForEach-Object { "[{0}: {1}GB livre de {2}GB]" -f $_.DriveLetter, [math]::Round($_.SizeRemaining / 1GB), [math]::Round($_.Size / 1GB) }) -join "; " } catch {}
try {
    $diskNumber = (Get-Partition -DriveLetter C).DiskNumber
    $dadosColetados.Modelo_Disco_Principal = (Get-Disk -Number $diskNumber).Model
} catch {
    $dadosColetados.Modelo_Disco_Principal = (Get-CimInstance -ClassName Win32_DiskDrive | Select-Object -First 1).Model
}
try {
    $smartStatus = Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
    if ($smartStatus) {
        $diskHealth = $smartStatus | ForEach-Object {
            try {
                $disk = Get-PhysicalDisk -InstanceId $_.InstanceName
                "$($disk.FriendlyName): $(if ($_.PredictFailure) { 'Falha Prevista' } else { 'OK' })"
            } catch {}
        }
        $dadosColetados.SaudeDiscoSMART = $diskHealth -join "; "
    } else {
        $dadosColetados.SaudeDiscoSMART = "Nao suportado ou sem permissao"
    }
} catch {}

Write-Host "Coletando informacoes de video e perifericos..."
try { $dadosColetados.GPU = Remove-Accents -InputString (Get-CimInstance -ClassName Win32_VideoController | Select-Object -First 1).Name } catch {}
try {
    $monitores = (Get-CimInstance -ClassName WmiMonitorID -Namespace root\wmi | ForEach-Object {
        $fabricante = -join ($_.ManufacturerName | ForEach-Object {[char]$_})
        $modelo = -join ($_.UserFriendlyName | ForEach-Object {[char]$_})
        $nomeLimpo = ("$fabricante - $modelo").Trim() -replace "`0"
        (Remove-Accents -InputString $nomeLimpo)
    }) -join "; "
    if ($monitores) { $dadosColetados.Monitores = $monitores } else { $dadosColetados.Monitores = "Nenhum monitor detectado" }
} catch { $dadosColetados.Monitores = "Falha ao ler monitores" }
try {
    $seriais = (Get-CimInstance -ClassName WmiMonitorID -Namespace root\wmi | ForEach-Object {
        $serial = (-join ($_.SerialNumberID | ForEach-Object {[char]$_})).Trim() -replace "`0"
        if ($serial) { (Remove-Accents -InputString $serial) }
    }) -join "; "
    if ($seriais) { $dadosColetados.NumeroSerieMonitores = $seriais } else { $dadosColetados.NumeroSerieMonitores = "Nenhum serial detectado" }
} catch {}
try {
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $dadosColetados.Resolucao_Tela = "{0}x{1}" -f $bounds.Width, $bounds.Height
} catch {
    $dadosColetados.Resolucao_Tela = 'Indisponivel'
}
try { $bat = Get-CimInstance -ClassName Win32_Battery; if ($bat) { $dadosColetados.Bateria = "$($bat.EstimatedChargeRemaining)%" } else { $dadosColetados.Bateria = "Desktop/Sem bateria" } } catch {}
try { $impressoras = (Get-Printer | ForEach-Object { Remove-Accents -InputString $_.Name }) -join "; "; if ($impressoras) { $dadosColetados.Impressoras = $impressoras } else { $dadosColetados.Impressoras = "Nenhuma impressora instalada" } } catch {}

Write-Host "Coletando informacoes de rede e seguranca..."
try {
    $adapter = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.IPAddress -notlike "169.254*" -and $_.IPEnabled } | Select-Object -First 1
    if ($adapter) {
        $dadosColetados.IP = ($adapter.IPAddress | Select-Object -First 1)
        $dadosColetados.GatewayPadrao = ($adapter.DefaultIPGateway | Select-Object -First 1)
        $dadosColetados.ServidoresDNS = $adapter.DNSServerSearchOrder -join ", "
        $dadosColetados.ServidorDHCP = $adapter.DHCPServer
        $dadosColetados.DHCPAtivado = $adapter.DHCPEnabled
        $dadosColetados.MAC = ((Get-CimInstance -ClassName Win32_NetworkAdapter -Filter "DeviceID = $($adapter.Index)").MACAddress).Replace(':', '-')
    }
} catch {}
try {
    $avProducts = @(); $avProducts += Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; $avProducts += Get-CimInstance -Namespace "root/SecurityCenter" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; $principalAV = $avProducts | Where-Object { $_.displayName -ne "Windows Defender" } | Select-Object -First 1; if (!$principalAV) { $principalAV = $avProducts | Select-Object -First 1 }; if ($principalAV) { $dadosColetados.Antivirus = Remove-Accents -InputString $principalAV.displayName; if (($principalAV.productState -band 0x1000) -or ($principalAV.productState -band 0x10)) { $dadosColetados.Antivirus_Status = "Ativo" } else { $dadosColetados.Antivirus_Status = "Inativo" } }
} catch {}
try { if (Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $true }) { $dadosColetados.Firewall_Ativo = "Sim" } else { $dadosColetados.Firewall_Ativo = "Nao" } } catch {}
try { $wsusPath = "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate"; if (Test-Path $wsusPath) { $wsus = Get-ItemProperty -Path $wsusPath -ErrorAction SilentlyContinue; if ($wsus.WUServer) { $dadosColetados.Usa_WSUS = "Sim"; $dadosColetados.Servidor_WSUS = $wsus.WUServer } } } catch {}
try {
    $admins = Get-LocalGroupMember -Group "Administradores" | Select-Object -ExpandProperty Name
    $dadosColetados.AdminsLocais = ($admins -replace ".*\\", "") -join "; "
} catch {}
try {
    $tcpPorts = (Get-NetTCPConnection -State Listen).LocalPort | Sort-Object -Unique
    if ($tcpPorts) { $dadosColetados.PortasTCP_Abertas = $tcpPorts -join ", " }
    $udpPorts = (Get-NetUDPEndpoint).LocalPort | Sort-Object -Unique
    if ($udpPorts) { $dadosColetados.PortasUDP_Abertas = $udpPorts -join ", " }
} catch {}

Write-Host "Coletando status de updates e processos..."
try {
    $updateSession = New-Object -ComObject "Microsoft.Update.Session"
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    $dadosColetados.UpdatesPendentes = $searchResult.Updates.Count
    $history = $updateSearcher.QueryHistory(0, 1)
    if ($history) {
        $lastInstall = $history | Where-Object { $_.Operation -eq 1 } | Sort-Object -Property Date -Descending | Select-Object -First 1
        if ($lastInstall) { $dadosColetados.UltimaInstalacaoUpdates = $lastInstall.Date.ToString("yyyy-MM-dd HH:mm") }
    }
} catch {}
try {
    $dadosColetados.ConsumoCPU_Percentual = (Get-CimInstance -ClassName Win32_Processor | Select-Object -ExpandProperty LoadPercentage -First 1)
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($os.TotalVisibleMemorySize -gt 0) {
        $dadosColetados.ConsumoRAM_Percentual = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 2)
    }
} catch {}
try {
    $processos = Get-Process
    $processosCPU = $processos | Sort-Object -Property CPU -Descending | Select-Object -First 5 | ForEach-Object { "{0} (CPU: {1:N2}s)" -f $_.ProcessName, $_.CPU }
    $dadosColetados.Top5ProcessosCPU = $processosCPU -join "; "

    $processosRAM = $processos | Sort-Object -Property WorkingSet -Descending | Select-Object -First 5 | ForEach-Object { "{0} (RAM: {1:N2}MB)" -f $_.ProcessName, ($_.WorkingSet / 1MB) }
    $dadosColetados.Top5ProcessosRAM = $processosRAM -join "; "
} catch {}


# --- NORMALIZAÇÃO FINAL: REMOVER ACENTOS DE TODOS OS CAMPOS DE TEXTO ---
Write-Host "Normalizando dados (removendo acentos)..."
foreach ($prop in $dadosColetados.PSObject.Properties) {
    if ($prop.Value -is [string]) {
        $prop.Value = Remove-Accents -InputString $prop.Value
    }
}

# --- GRAVAÇÃO SEGURA NO HTML COM FILE LOCKING E MARCADORES ---

Write-Host "Coleta finalizada. Tentando gravar de forma segura no arquivo: $arquivoHtml"

$startMarker = "//<DATA_START>"
$endMarker = "//<DATA_END>"
$tentativas = 5
$esperaSegundos = 3
$sucesso = $false

if (-not (Test-Path $arquivoHtml)) {
    Write-Error "Arquivo HTML template não encontrado em $arquivoHtml. Crie o arquivo a partir do código fornecido."
    return
}

for ($i = 1; $i -le $tentativas; $i++) {
    $fileStream = $null
    try {
        $fileStream = [System.IO.File]::Open($arquivoHtml, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        Write-Host "Bloqueio de arquivo obtido na tentativa $i."
        
        $streamReader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8, $true, 1024, $true)
        $htmlContent = $streamReader.ReadToEnd()
        $streamReader.Dispose()

        $startIndex = $htmlContent.IndexOf($startMarker) + $startMarker.Length
        $endIndex = $htmlContent.IndexOf($endMarker, $startIndex)

        if ($startIndex -ge $startMarker.Length -and $endIndex -ge 0) {
            
            $dataBlock = $htmlContent.Substring($startIndex, $endIndex - $startIndex)
            $startIndexJson = $dataBlock.IndexOf('[')
            $endIndexJson = $dataBlock.LastIndexOf(']')
            
            [System.Collections.ArrayList]$dadosAtuais = @()
            
            if ($startIndexJson -ne -1 -and $endIndexJson -ne -1 -and $endIndexJson -gt $startIndexJson) {
                $jsonString = $dataBlock.Substring($startIndexJson, $endIndexJson - $startIndexJson + 1)
                if ($jsonString.Trim() -ne "[]") {
                    try {
                        $dadosConvertidos = $jsonString | ConvertFrom-Json -ErrorAction Stop
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

            $dadosFiltrados = @($dadosAtuais | Where-Object { $_.Computador -ne $dadosColetados.Computador })
            
            $novosDados = $dadosFiltrados + $dadosColetados
            
            $novoArrayJson = $novosDados | ConvertTo-Json -Depth 10 -Compress
            
            $before = $htmlContent.Substring(0, $startIndex)
            $after = $htmlContent.Substring($endIndex)
            $novoHtmlContent = $before + "`r`n    var inventoryData = " + $novoArrayJson + ";`r`n    " + $after

            $fileStream.Seek(0, 'Begin') | Out-Null
            $fileStream.SetLength(0)
            $streamWriter = [System.IO.StreamWriter]::new($fileStream, [System.Text.Encoding]::UTF8)
            $streamWriter.Write($novoHtmlContent)
            $streamWriter.Flush()
            $streamWriter.Close()
            
            Write-Host "Arquivo HTML atualizado com sucesso."
            $sucesso = $true
            break 
        } else {
            Write-Warning "Não foi possível encontrar os marcadores de dados no arquivo HTML. A gravação foi cancelada."
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

if (-not $sucesso) { Write-Error "NÃO FOI POSSÍVEL GRAVAR NO ARQUIVO HTML após $tentativas tentativas." -ErrorAction Stop }

# ============================
# Salvar inventário individual
# ============================

try {
    $jsonDestino = "P:\ADMIN\parque3.0\inventario\$($env:COMPUTERNAME).json"
    $json = $dadosColetados | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText($jsonDestino, $json, [System.Text.Encoding]::UTF8)
    Write-Host "Inventário individual salvo em $jsonDestino"
}
catch {
    Write-Warning "Falha ao salvar inventário individual: $($_.Exception.Message)"
}

# ============================
# Salvar inventário individual em HTML
# ============================

try {
    $htmlDestino = "P:\ADMIN\parque3.0\inventario\$($env:COMPUTERNAME).html"

    $categorias = [ordered]@{
        "Computador e Usuario" = @("Computador", "Usuario", "Dominio_ou_Grupo")
        "Sistema Operacional"  = @("SO", "Build", "Arquitetura", "Data_Instalacao", "Uptime_Formatado", "Status_Ativacao", "Canal_Licenca", "Chave_Parcial", "Chave_OEM_BIOS")
        "Status e Desempenho" = @("ConsumoCPU_Percentual", "ConsumoRAM_Percentual", "Top5ProcessosCPU", "Top5ProcessosRAM", "SaudeDiscoSMART")
        "Windows Update" = @("UpdatesPendentes", "UltimaInstalacaoUpdates")
        "Hardware: Placa-Mae e Chassis" = @("Computador_Fabricante", "Computador_Modelo", "Computador_Serial", "Chassis_Tipo", "PlacaMae_Fabricante", "PlacaMae_Modelo", "PlacaMae_Serial", "BIOS_Versao", "BIOS_Data")
        "Hardware: CPU e RAM" = @("CPU", "CPU_Cores", "CPU_Threads", "CPU_Clock_MHz", "RAM_GB_Total", "Qtd_Pentes", "RAM_Detalhes")
        "Hardware: Armazenamento" = @("Armazenamento_C_GB", "Espaco_Livre_C_GB", "Espaco_Livre_C_Perc", "Discos_Fisicos", "Volumes", "Modelo_Disco_Principal")
        "Hardware: Perifericos e Video" = @("GPU", "Monitores", "NumeroSerieMonitores", "Resolucao_Tela", "Bateria", "Impressoras")
        "Rede e Seguranca" = @("IP", "GatewayPadrao", "ServidoresDNS", "ServidorDHCP", "DHCPAtivado", "MAC", "Antivirus", "Antivirus_Status", "Firewall_Ativo", "Usa_WSUS", "Servidor_WSUS", "AdminsLocais", "PortasTCP_Abertas", "PortasUDP_Abertas")
    }

    $dadosAgrupados = [ordered]@{}
    foreach ($titulo in $categorias.Keys) {
        $dadosAgrupados[$titulo] = [ordered]@{}
    }
    $dadosAgrupados["Outras Informacoes"] = [ordered]@{}

    foreach ($prop in $dadosColetados.PSObject.Properties) {
        $key = $prop.Name
        $value = $prop.Value
        $categoriaEncontrada = $null
        foreach ($categoria in $categorias.Keys) {
            if ($categorias[$categoria] -contains $key) {
                $categoriaEncontrada = $categoria
                break
            }
        }
        if ($categoriaEncontrada) {
            $dadosAgrupados[$categoriaEncontrada][$key] = $value
        } else {
            if ($key -notin @("RelatorioHTML", "DataHora_Coleta", "Uptime_Horas")) {
                 $dadosAgrupados["Outras Informacoes"][$key] = $value
            }
        }
    }

    Add-Type -AssemblyName System.Web
    $secoesHtml = ""
    foreach ($titulo in $dadosAgrupados.Keys) {
        $dadosDaSecao = $dadosAgrupados[$titulo]
        if ($dadosDaSecao.Count -eq 0) { continue }

        $secoesHtml += "<h2>$titulo</h2><table>"
        foreach ($item in $dadosDaSecao.GetEnumerator()) {
            $key = $item.Name
            $value = $item.Value
            if ($value -is [array]) {
                $value = $value -join "<br>"
            }
            $valorExibido = if ([string]::IsNullOrWhiteSpace($value)) { "Indisponivel" } elseif ($value -eq "Nao suportado ou sem permissao") { "Dados indisponíveis" } else { [System.Web.HttpUtility]::HtmlEncode($value) }
            $secoesHtml += "<tr><td><b>$key</b></td><td>$valorExibido</td></tr>"
        }
        $secoesHtml += "</table>"
    }

    $htmlContent = @"
<!DOCTYPE html>
<html lang='pt-BR'>
<head>
<meta charset='UTF-8'>
<title>Inventario - $($dadosColetados.Computador)</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; margin: 0; background-color: #f4f7f9; color: #333; }
.container { max-width: 1000px; margin: 40px auto; padding: 20px; background-color: #fff; box-shadow: 0 4px 8px rgba(0,0,0,0.1); border-radius: 8px; }
h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
h2 { font-size: 1.4em; color: #34495e; margin-top: 40px; margin-bottom: 15px; padding-bottom: 5px; border-bottom: 1px solid #bdc3c7; }
p.subtitle { font-style: italic; color: #7f8c8d; margin-top: -10px; margin-bottom: 30px; }
table { width: 100%; border-collapse: collapse; margin-top: 10px; }
td { padding: 10px 12px; border: 1px solid #e0e0e0; vertical-align: top; word-break: break-all; }
tr:nth-child(even) { background-color: #f8f9fa; }
td:first-child { width: 25%; background-color: #ecf0f1; font-weight: bold; color: #34495e; }
</style>
</head>
<body>
    <div class='container'>
        <h1>Inventario - $($dadosColetados.Computador)</h1>
        <p class='subtitle'><i>Gerado em $($dadosColetados.DataHora_Coleta)</i></p>
        $secoesHtml
    </div>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($htmlDestino, $htmlContent, [System.Text.Encoding]::UTF8)

    Write-Host "Relatório individual salvo em $htmlDestino"
}
catch {
    Write-Warning "Falha ao salvar relatório HTML individual: $($_.Exception.Message)"
}
$dadosColetados | Add-Member -NotePropertyName "RelatorioHTML" -NotePropertyValue ".\inventario\$($env:COMPUTERNAME).html"
$stopwatch.Stop()
Write-Host ("`nTempo total de execucao: {0:N2} segundos" -f $stopwatch.Elapsed.TotalSeconds)