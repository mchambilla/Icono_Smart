param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "dist\SmartSouthTray.exe")
)

$ErrorActionPreference = "Stop"

$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = $compilerCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
    throw "No se encontró el compilador de .NET Framework. Instala .NET Framework 4.x para compilar el bootstrapper."
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$arguments = @(
    "/nologo",
    "/target:winexe",
    "/out:$OutputPath",
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.IO.Compression.dll",
    "/reference:System.IO.Compression.FileSystem.dll",
    "/reference:System.Web.Extensions.dll",
    "/reference:System.Windows.Forms.dll",
    (Join-Path $PSScriptRoot "SmartSouthTrayBootstrapper.cs")
)

& $compiler $arguments
if ($LASTEXITCODE -ne 0) {
    throw "Falló la compilación del bootstrapper (código $LASTEXITCODE)."
}

Write-Host "Bootstrapper generado: $OutputPath"
