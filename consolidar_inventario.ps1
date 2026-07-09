$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$cfg = @{
    PROJECT_DIR        = $scriptDir
    HTML_FILE          = 'inventario_web.html'
    HTML_TEMPLATE_FILE = 'inventario_web.template.html'
    INVENTORY_DIR      = 'inventario'
    MARCADOR_DADOS_INI = '//<DATA_START>'
    MARCADOR_DADOS_FIM = '//<DATA_END>'
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

function Resolve-CfgPath([string]$PathValue, [string]$DefaultValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { $PathValue = $DefaultValue }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $cfg.PROJECT_DIR $PathValue)
}

$htmlFile = Resolve-CfgPath $cfg.HTML_FILE 'inventario_web.html'
$templateFile = Resolve-CfgPath $cfg.HTML_TEMPLATE_FILE 'inventario_web.template.html'
$inventoryDir = Resolve-CfgPath $cfg.INVENTORY_DIR 'inventario'
$aggregatedJsonFile = Join-Path $inventoryDir 'inventario_web.json'
$startMarker = [string]$cfg.MARCADOR_DADOS_INI
$endMarker = [string]$cfg.MARCADOR_DADOS_FIM

if (-not (Test-Path $inventoryDir)) {
    throw "Pasta de inventario nao encontrada: $inventoryDir"
}

if (-not (Test-Path $htmlFile)) {
    if (Test-Path $templateFile) {
        Copy-Item -Path $templateFile -Destination $htmlFile -Force
        Write-Host "HTML operacional criado a partir do template: $htmlFile"
    } else {
        throw "Arquivo HTML nao encontrado em $htmlFile e template nao encontrado em $templateFile"
    }
}

$itemsByComputer = @{}
$jsonFiles = Get-ChildItem -Path $inventoryDir -Filter '*.json' -File |
    Where-Object { $_.Name -ne 'inventario_web.json' }

foreach ($file in $jsonFiles) {
    try {
        $raw = Get-Content -Path $file.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Warning "Ignorando JSON vazio: $($file.FullName)"
            continue
        }
        $item = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($item -is [array]) {
            Write-Warning "Ignorando JSON com array inesperado: $($file.FullName)"
            continue
        }
        if (-not $item.Computador) {
            Write-Warning "Ignorando JSON sem campo Computador: $($file.FullName)"
            continue
        }
        $itemsByComputer[[string]$item.Computador] = $item
    } catch {
        Write-Warning "Ignorando JSON invalido: $($file.FullName) - $($_.Exception.Message)"
    }
}

$inventoryData = @($itemsByComputer.GetEnumerator() |
    Sort-Object Name |
    ForEach-Object { $_.Value })

$json = if ($inventoryData.Count -eq 0) {
    '[]'
} else {
    ConvertTo-Json -InputObject $inventoryData -Depth 20
}

[System.IO.File]::WriteAllText($aggregatedJsonFile, $json, [System.Text.UTF8Encoding]::new($false))

$lockFile = "$htmlFile.lock"
$lockStream = $null
try {
    $lockStream = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    $html = [System.IO.File]::ReadAllText($htmlFile, [System.Text.Encoding]::UTF8)
    $startIndex = $html.IndexOf($startMarker)
    if ($startIndex -lt 0) { throw "Marcador inicial nao encontrado: $startMarker" }
    $afterStartIndex = $startIndex + $startMarker.Length
    $endIndex = $html.IndexOf($endMarker, $afterStartIndex)
    if ($endIndex -lt 0) { throw "Marcador final nao encontrado: $endMarker" }

    $backupFile = "$htmlFile.$(Get-Date -Format 'yyyyMMddHHmmss').bak.html"
    Copy-Item -Path $htmlFile -Destination $backupFile -Force

    $before = $html.Substring(0, $afterStartIndex)
    $after = $html.Substring($endIndex)
    $newBlock = "`r`n    var inventoryData = $json;`r`n    "
    $newHtml = $before + $newBlock + $after

    [System.IO.File]::WriteAllText($htmlFile, $newHtml, [System.Text.UTF8Encoding]::new($true))
} finally {
    if ($lockStream) {
        $lockStream.Close()
        $lockStream.Dispose()
    }
}

Write-Host "Inventario consolidado com $($inventoryData.Count) registros."
Write-Host "JSON agregado: $aggregatedJsonFile"
Write-Host "HTML atualizado: $htmlFile"
