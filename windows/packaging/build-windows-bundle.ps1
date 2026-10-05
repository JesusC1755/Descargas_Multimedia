# ==============================================================================
# build-windows-bundle.ps1
# Script PowerShell para compilar y empaquetar Media Downloader en Windows
# ==============================================================================

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$SkipZip
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Resolve-Path "$ScriptDir\..\.."
Set-Location $ProjectRoot

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   Media Downloader - Empaquetador para Windows     " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Compilación de Flutter en modo Release (a menos que se indique -SkipBuild)
$ReleaseDir = "$ProjectRoot\build\windows\x64\runner\Release"

if (-not $SkipBuild) {
    Write-Host "`n[*] Verificando Flutter en el sistema..." -ForegroundColor Yellow
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Error "No se encontró 'flutter' en el PATH. Asegúrate de tener instalado el SDK de Flutter."
    }

    Write-Host "[*] Compilando aplicación Flutter para Windows (Release)..." -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error durante 'flutter build windows --release'."
    }
} else {
    Write-Host "`n[*] Omitiendo compilación (-SkipBuild especificado)." -ForegroundColor Gray
}

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "No se encontró el directorio de release: $ReleaseDir"
}

# 2. Preparar carpeta 'tools' dentro del bundle compilado
$ToolsDir = "$ReleaseDir\tools"
if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
}
Write-Host "`n[✔] Directorio de herramientas de destino: $ToolsDir" -ForegroundColor Green

# 3. Descarga / Copia de binarios portables
$LocalCache = "$ProjectRoot\windows\tools"
if (-not (Test-Path $LocalCache)) {
    New-Item -ItemType Directory -Path $LocalCache -Force | Out-Null
}

# Helper para descargar si no existe
function Ensure-Tool {
    param(
        [string]$ToolName,
        [string]$Url,
        [switch]$IsZip,
        [string]$ZipInternalPath
    )

    $DestFile = "$ToolsDir\$ToolName"
    $CacheFile = "$LocalCache\$ToolName"

    if (Test-Path $CacheFile) {
        Write-Host "    [✔] Usando caché local para $ToolName" -ForegroundColor Green
        Copy-Item -Path $CacheFile -Destination $DestFile -Force
        return
    }

    if (Test-Path $DestFile) {
        Write-Host "    [✔] $ToolName ya está presente en tools/" -ForegroundColor Green
        return
    }

    Write-Host "    [*] Descargando $ToolName desde $Url..." -ForegroundColor Yellow
    $TempDownload = "$env:TEMP\$ToolName.tmp"

    if ($IsZip) {
        $ZipTemp = "$env:TEMP\temp_$ToolName.zip"
        Invoke-WebRequest -Uri $Url -OutFile $ZipTemp -UseBasicParsing
        $ExtractDir = "$env:TEMP\extracted_$ToolName"
        Expand-Archive -Path $ZipTemp -DestinationPath $ExtractDir -Force
        $Found = Get-ChildItem -Path $ExtractDir -Filter $ToolName -Recurse | Select-Object -First 1
        if ($Found) {
            Copy-Item -Path $Found.FullName -Destination $CacheFile -Force
            Copy-Item -Path $Found.FullName -Destination $DestFile -Force
        } else {
            Write-Error "No se encontró $ToolName dentro del archivo descargado."
        }
        Remove-Item -Path $ZipTemp -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $CacheFile -UseBasicParsing
        Copy-Item -Path $CacheFile -Destination $DestFile -Force
    }

    Write-Host "    [✔] $ToolName preparado con éxito." -ForegroundColor Green
}

Write-Host "`n[*] Sincronizando binarios portables en tools/..." -ForegroundColor Cyan

# A. yt-dlp.exe
Ensure-Tool -ToolName "yt-dlp.exe" `
            -Url "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"

# B. node.exe (EJS Runtime oficial)
Ensure-Tool -ToolName "node.exe" `
            -Url "https://nodejs.org/dist/v20.18.0/win-x64/node.exe"

# C. ffmpeg.exe y ffprobe.exe
$FfmpegZipUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
Ensure-Tool -ToolName "ffmpeg.exe" -Url $FfmpegZipUrl -IsZip
Ensure-Tool -ToolName "ffprobe.exe" -Url $FfmpegZipUrl -IsZip

# 4. Generar paquete comprimido .ZIP (Portable)
$DistDir = "$ProjectRoot\dist"
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

if (-not $SkipZip) {
    $ZipOutput = "$DistDir\MediaDownloader-Windows-x64-Portable.zip"
    Write-Host "`n[*] Generando archivo ZIP portable en: $ZipOutput..." -ForegroundColor Yellow
    if (Test-Path $ZipOutput) { Remove-Item $ZipOutput -Force }
    Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipOutput -CompressionLevel Optimal
    Write-Host "[✔] Paquete portable generado exitosamente:" -ForegroundColor Green
    Write-Host "    $ZipOutput" -ForegroundColor Cyan
}

Write-Host "`n====================================================" -ForegroundColor Cyan
Write-Host "   ¡Empaquetado completado exitosamente!            " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "• Archivo ZIP para distribución: dist\MediaDownloader-Windows-x64-Portable.zip"
Write-Host "• Carpeta para prueba directa:   $ReleaseDir"
Write-Host "• Ejecutable principal:          $ReleaseDir\media_downloader.exe`n"
