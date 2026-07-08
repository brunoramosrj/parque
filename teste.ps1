# Helper function to run and time a script block
function Measure-CommandExecution {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)]
        [string]$Description
    )
    Write-Host "Testando: $Description"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $ScriptBlock | Out-Null
    } catch {
        Write-Warning "Falha durante o teste '$Description': $($_.Exception.Message)"
    }
    $stopwatch.Stop()
    Write-Host ("--> Tempo TOTAL de execução: {0:N2} segundos" -f $stopwatch.Elapsed.TotalSeconds)
    Write-Host "-----------------------------------------------------------------"
}

Write-Host "Iniciando teste de velocidade da coleta COMPLETA..."
Write-Host "==========================================================================="

# Teste 1: Coleta Completa com Get-WmiObject (Método Antigo e Estável)
Measure-CommandExecution -Description "Coleta Completa (Get-WmiObject)" -ScriptBlock {
    try { Get-WmiObject -Class Win32_ComputerSystem } catch {}
    try { Get-WmiObject -Class Win32_BIOS } catch {}
    try { Get-WmiObject -Class Win32_SystemEnclosure } catch {}
    try { Get-WmiObject -Query "SELECT PartialProductKey, Description, LicenseStatus FROM SoftwareLicensingProduct WHERE ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus = 1" } catch {}
    try { Get-WmiObject -Class Win32_OperatingSystem } catch {}
    try { Get-WmiObject -Class Win32_Processor } catch {}
    try { Get-WmiObject -Class Win32_BaseBoard } catch {}
    try { Get-WmiObject -Class Win32_PhysicalMemory } catch {}
    try { Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'" } catch {}
    try { Get-PhysicalDisk } catch {}
    try { Get-Volume } catch {}
    try { Get-WmiObject -Class Win32_DiskDrive } catch {}
    try { Get-WmiObject -Class Win32_VideoController } catch {}
    try { Get-WmiObject -Class WmiMonitorID -Namespace root\wmi } catch {}
    try { Get-WmiObject -Class Win32_Battery } catch {}
    try { Get-Printer } catch {}
    try { Get-WmiObject -Namespace "root/SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; Get-WmiObject -Namespace "root/SecurityCenter" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue } catch {}
    try { Get-NetFirewallProfile } catch {}
    try { Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue } catch {}
    try { Get-LocalGroupMember -Group "Administradores" } catch {}
    try { Get-NetTCPConnection -State Listen; Get-NetUDPEndpoint } catch {}
    try {
        $updateSession = New-Object -ComObject "Microsoft.Update.Session"
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    } catch {}
    try { Get-WmiObject -Class Win32_Processor } catch {}
    try { Get-WmiObject -Class Win32_OperatingSystem } catch {}
    try { Get-Process } catch {}
}

# Teste 2: Coleta Completa com Get-CimInstance (Método Moderno)
Measure-CommandExecution -Description "Coleta Completa (Get-CimInstance)" -ScriptBlock {
    try { Get-CimInstance -ClassName Win32_ComputerSystem } catch {}
    try { Get-CimInstance -ClassName Win32_BIOS } catch {}
    try { Get-CimInstance -ClassName Win32_SystemEnclosure } catch {}
    try { Get-CimInstance -Query "SELECT PartialProductKey, Description, LicenseStatus FROM SoftwareLicensingProduct WHERE ApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f' and LicenseStatus = 1" } catch {}
    try { Get-CimInstance -ClassName Win32_OperatingSystem } catch {}
    try { Get-CimInstance -ClassName Win32_Processor } catch {}
    try { Get-CimInstance -ClassName Win32_BaseBoard } catch {}
    try { Get-CimInstance -ClassName Win32_PhysicalMemory } catch {}
    try { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" } catch {}
    try { Get-PhysicalDisk } catch {}
    try { Get-Volume } catch {}
    try { Get-CimInstance -ClassName Win32_DiskDrive } catch {}
    try { Get-CimInstance -ClassName Win32_VideoController } catch {}
    try { Get-CimInstance -ClassName WmiMonitorID -Namespace root\wmi } catch {}
    try { Get-CimInstance -ClassName Win32_Battery } catch {}
    try { Get-Printer } catch {}
    try { Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue; Get-CimInstance -Namespace "root/SecurityCenter" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue } catch {}
    try { Get-NetFirewallProfile } catch {}
    try { Get-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue } catch {}
    try { Get-LocalGroupMember -Group "Administradores" } catch {}
    try { Get-NetTCPConnection -State Listen; Get-NetUDPEndpoint } catch {}
    try {
        $updateSession = New-Object -ComObject "Microsoft.Update.Session"
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $updateSearcher.Search("IsInstalled=0 and Type='Software'")
    } catch {}
    try { Get-CimInstance -ClassName Win32_Processor } catch {}
    try { Get-CimInstance -ClassName Win32_OperatingSystem } catch {}
    try { Get-Process } catch {}
}

Write-Host "==========================================================================="
Write-Host "Teste de velocidade finalizado."
