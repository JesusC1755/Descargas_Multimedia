#!/usr/bin/env bash
# ==============================================================================
# Script para descargar los binarios portables de Windows (yt-dlp, FFmpeg, Node)
# Puede ejecutarse desde Linux, macOS o Git Bash en Windows.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$SCRIPT_DIR/../tools}"

mkdir -p "$TARGET_DIR"

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║      Descarga de Herramientas Portables de Windows para CLI        ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "Directorio destino: $TARGET_DIR"
echo ""

# 1. yt-dlp.exe (Standalone oficial de GitHub)
if [ ! -f "$TARGET_DIR/yt-dlp.exe" ]; then
    echo "[*] [1/3] Descargando yt-dlp.exe..."
    curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -o "$TARGET_DIR/yt-dlp.exe"
    echo "    ✔ yt-dlp.exe descargado."
else
    echo "    ✔ yt-dlp.exe ya presente en el destino."
fi

# 2. node.exe (Standalone oficial de NodeJS para resolución de firmas EJS)
if [ ! -f "$TARGET_DIR/node.exe" ]; then
    echo "[*] [2/3] Descargando node.exe portable (v20.18.0 x64)..."
    curl -fsSL "https://nodejs.org/dist/v20.18.0/win-x64/node.exe" -o "$TARGET_DIR/node.exe"
    echo "    ✔ node.exe descargado."
else
    echo "    ✔ node.exe ya presente en el destino."
fi

# 3. ffmpeg.exe y ffprobe.exe (Compilación estática oficial de BtbN)
if [ ! -f "$TARGET_DIR/ffmpeg.exe" ] || [ ! -f "$TARGET_DIR/ffprobe.exe" ]; then
    echo "[*] [3/3] Descargando FFmpeg + FFprobe para Windows (x64)..."
    TEMP_ZIP=$(mktemp --suffix=.zip)
    curl -fsSL "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip" -o "$TEMP_ZIP"
    unzip -q -o -j "$TEMP_ZIP" "*/bin/ffmpeg.exe" "*/bin/ffprobe.exe" -d "$TARGET_DIR/"
    rm -f "$TEMP_ZIP"
    echo "    ✔ ffmpeg.exe y ffprobe.exe extraídos."
else
    echo "    ✔ ffmpeg.exe y ffprobe.exe ya presentes en el destino."
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║          Herramientas Portables Listas para Windows                ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
ls -lh "$TARGET_DIR"
