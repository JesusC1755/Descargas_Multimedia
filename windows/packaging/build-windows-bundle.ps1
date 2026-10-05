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
$ProjectRoot = (Resolve-Path "$ScriptDir\..\..").Path
Set-Location $ProjectRoot

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   Media Downloader - Empaquetador para Windows     " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Compilacion de Flutter en modo Release (a menos que se indique -SkipBuild)
$ReleaseDir = "$ProjectRoot\build\windows\x64\runner\Release"

if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "[*] Verificando Flutter en el sistema..." -ForegroundColor Yellow
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        Write-Error "No se encontro 'flutter' en el PATH. Asegurate de tener instalado el SDK de Flutter."
    }

    Write-Host "[*] Resolviendo paquetes (flutter pub get)..." -ForegroundColor Yellow
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Fallo la resolucion de paquetes con el archivo de bloqueo existente."
        Write-Host "[*] Regenerando dependencias para la version local de Flutter..." -ForegroundColor Yellow
        if (Test-Path "$ProjectRoot\pubspec.lock") {
            Remove-Item -Path "$ProjectRoot\pubspec.lock" -Force -ErrorAction SilentlyContinue
            flutter pub get
        }
    }

    # Verificacion de permisos de symlinks en Windows
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $devModeReg = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense

    if (-not $isAdmin -and ($devModeReg -ne 1)) {
        Write-Warning "El 'Modo Desarrollador' de Windows no parece estar habilitado."
        Write-Host "  Flutter requiere permisos para crear enlaces simbolicos (symlinks)." -ForegroundColor Yellow
        Write-Host "  Para activarlo: ejecuta 'start ms-settings:developers' y activa 'Modo de desarrollador'." -ForegroundColor Cyan
        Write-Host "  O bien: ejecuta este script haciendo clic derecho -> 'Ejecutar como administrador'." -ForegroundColor Cyan
        Write-Host ""
    }

    Write-Host "[*] Compilando aplicacion Flutter para Windows (Release)..." -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[!] La compilacion fallo. Si el error menciona 'symlink support':" -ForegroundColor Red
        Write-Host "    - Activa el Modo Desarrollador en Windows (Configuracion -> Para desarrolladores -> Modo de desarrollador)." -ForegroundColor Yellow
        Write-Host "    - O ejecuta el script haciendo clic derecho en 'build-windows-bundle.bat' -> 'Ejecutar como administrador'." -ForegroundColor Yellow
        Write-Error "Error durante 'flutter build windows --release'."
    }
} else {
    Write-Host ""
    Write-Host "[*] Omitiendo compilacion (-SkipBuild especificado)." -ForegroundColor Gray
}

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "No se encontro el directorio de release: $ReleaseDir"
}

# 2. Preparar carpeta 'tools' dentro del bundle compilado
$ToolsDir = "$ReleaseDir\tools"
if (-not (Test-Path $ToolsDir)) {
    New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
}
Write-Host ""
Write-Host "[+] Directorio de herramientas de destino: $ToolsDir" -ForegroundColor Green

# 3. Descarga / Copia de binarios portables
$LocalCache = "$ProjectRoot\windows\tools"
if (-not (Test-Path $LocalCache)) {
    New-Item -ItemType Directory -Path $LocalCache -Force | Out-Null
}

function Ensure-Tool {
    param(
        [Parameter(Mandatory=$true)][string]$ToolName,
        [Parameter(Mandatory=$true)][string]$Url,
        [switch]$IsZip
    )

    $DestFile = Join-Path $ToolsDir $ToolName
    $CacheFile = Join-Path $LocalCache $ToolName

    if (Test-Path $CacheFile) {
        Write-Host "    [OK] Usando cache local para $ToolName" -ForegroundColor Green
        Copy-Item -Path $CacheFile -Destination $DestFile -Force
        return
    }

    if (Test-Path $DestFile) {
        Write-Host "    [OK] $ToolName ya esta presente en tools/" -ForegroundColor Green
        return
    }

    Write-Host "    [*] Descargando $ToolName desde $Url..." -ForegroundColor Yellow

    if ($IsZip) {
        $ZipTemp = Join-Path $env:TEMP "temp_$ToolName.zip"
        Invoke-WebRequest -Uri $Url -OutFile $ZipTemp -UseBasicParsing
        $ExtractDir = Join-Path $env:TEMP "extracted_$ToolName"
        if (Test-Path $ExtractDir) { Remove-Item -Path $ExtractDir -Recurse -Force }
        Expand-Archive -Path $ZipTemp -DestinationPath $ExtractDir -Force
        $Found = Get-ChildItem -Path $ExtractDir -Filter $ToolName -Recurse | Select-Object -First 1
        if ($Found) {
            Copy-Item -Path $Found.FullName -Destination $CacheFile -Force
            Copy-Item -Path $Found.FullName -Destination $DestFile -Force
        } else {
            Write-Error "No se encontro $ToolName dentro del archivo descargado."
        }
        Remove-Item -Path $ZipTemp -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $ExtractDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $CacheFile -UseBasicParsing
        Copy-Item -Path $CacheFile -Destination $DestFile -Force
    }

    Write-Host "    [OK] $ToolName preparado con exito." -ForegroundColor Green
}

Write-Host ""
Write-Host "[*] Sincronizando binarios portables en tools/..." -ForegroundColor Cyan

# A. yt-dlp.exe
Ensure-Tool -ToolName "yt-dlp.exe" -Url "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"

# B. node.exe (EJS Runtime oficial)
Ensure-Tool -ToolName "node.exe" -Url "https://nodejs.org/dist/v20.18.0/win-x64/node.exe"

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
    Write-Host ""
    Write-Host "[*] Generando archivo ZIP portable en: $ZipOutput..." -ForegroundColor Yellow
    if (Test-Path $ZipOutput) { Remove-Item $ZipOutput -Force }
    Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipOutput -CompressionLevel Optimal
    Write-Host "[+] Paquete portable generado exitosamente:" -ForegroundColor Green
    Write-Host "    $ZipOutput" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   Empaquetado completado exitosamente!             " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "- Archivo ZIP para distribucion: dist\MediaDownloader-Windows-x64-Portable.zip"
Write-Host "- Carpeta para prueba directa:   $ReleaseDir"
Write-Host "- Ejecutable principal:          $ReleaseDir\media_downloader.exe"
Write-Host ""
