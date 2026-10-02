param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v?\d+\.\d+\.\d+([+-][0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [string]$OutputPath
)

$ErrorActionPreference = "Stop"
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot "dist\SmartSouthTray.zip"
}

$scriptPath = Join-Path $PSScriptRoot "SmartSouthTray.ps1"
$logoPath = Join-Path $PSScriptRoot "Logo.png"
if (-not (Test-Path $scriptPath)) {
    throw "No se encontró SmartSouthTray.ps1."
}
if (-not (Test-Path $logoPath)) {
    throw "No se encontró Logo.png."
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$stagingPath = Join-Path ([System.IO.Path]::GetTempPath()) ("SmartSouthTray-release-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingPath | Out-Null

try {
    Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $stagingPath "SmartSouthTray.ps1")
    Copy-Item -LiteralPath $logoPath -Destination (Join-Path $stagingPath "Logo.png")
    Set-Content -LiteralPath (Join-Path $stagingPath "version.txt") -Value $Version.TrimStart("v") -Encoding ASCII

    if (Test-Path $OutputPath) {
        Remove-Item -LiteralPath $OutputPath -Force
    }
    Compress-Archive -Path (Join-Path $stagingPath "*") -DestinationPath $OutputPath -CompressionLevel Optimal
}
finally {
    Remove-Item -LiteralPath $stagingPath -Recurse -Force
}

Write-Host "Paquete listo para adjuntar al Release: $OutputPath"
