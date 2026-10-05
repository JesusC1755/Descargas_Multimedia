#!/usr/bin/env bash
# ==============================================================================
# install-desktop.sh
# Instala el acceso directo (.desktop) e iconos del sistema en Linux (GNOME/KDE/XFCE)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Buscar el ejecutable en Release o Debug
BIN_PATH=""
if [ -f "$PROJECT_ROOT/build/linux/x64/release/bundle/media_downloader" ]; then
    BIN_PATH="$PROJECT_ROOT/build/linux/x64/release/bundle/media_downloader"
elif [ -f "$PROJECT_ROOT/build/linux/x64/debug/bundle/media_downloader" ]; then
    BIN_PATH="$PROJECT_ROOT/build/linux/x64/debug/bundle/media_downloader"
else
    echo "No se encontró el binario compilado. Ejecuta primero: flutter build linux --release"
    BIN_PATH="$PROJECT_ROOT/build/linux/x64/release/bundle/media_downloader"
fi

echo "==> Configurando integración de escritorio para Media Downloader..."

# 1. Crear directorios estándar XDG si no existen
ICON_DIR="$HOME/.local/share/icons/hicolor"
APPS_DIR="$HOME/.local/share/applications"

mkdir -p "$APPS_DIR"
mkdir -p "$ICON_DIR/32x32/apps"
mkdir -p "$ICON_DIR/64x64/apps"
mkdir -p "$ICON_DIR/128x128/apps"
mkdir -p "$ICON_DIR/256x256/apps"
mkdir -p "$ICON_DIR/512x512/apps"

# 2. Copiar iconos en todas las resoluciones
cp "$PROJECT_ROOT/assets/icons/app_icon_32.png"  "$ICON_DIR/32x32/apps/com.example.media_downloader.png"
cp "$PROJECT_ROOT/assets/icons/app_icon_64.png"  "$ICON_DIR/64x64/apps/com.example.media_downloader.png"
cp "$PROJECT_ROOT/assets/icons/app_icon_128.png" "$ICON_DIR/128x128/apps/com.example.media_downloader.png"
cp "$PROJECT_ROOT/assets/icons/app_icon_256.png" "$ICON_DIR/256x256/apps/com.example.media_downloader.png"
cp "$PROJECT_ROOT/assets/icons/app_icon.png"     "$ICON_DIR/512x512/apps/com.example.media_downloader.png"

# Copias de alias simples para compatibilidad
cp "$PROJECT_ROOT/assets/icons/app_icon.png"     "$ICON_DIR/512x512/apps/media_downloader.png"

# 3. Generar el archivo .desktop con rutas absolutas
DESKTOP_FILE="$APPS_DIR/com.example.media_downloader.desktop"
cat <<EOF > "$DESKTOP_FILE"
[Desktop Entry]
Version=1.0
Type=Application
Name=Media Downloader
Comment=Descargas de Audio y Video con yt-dlp y FFmpeg
Exec=$BIN_PATH %u
Icon=com.example.media_downloader
Terminal=false
Categories=AudioVideo;Audio;Video;Network;
StartupWMClass=com.example.media_downloader
Keywords=youtube;downloader;video;audio;mp3;mp4;
EOF

chmod +x "$DESKTOP_FILE"

# 4. Actualizar bases de datos de escritorio e iconos
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$ICON_DIR" >/dev/null 2>&1 || true
fi

echo "[✔] Integración completada con éxito."
echo "    - Archivo de acceso directo: $DESKTOP_FILE"
echo "    - Icono del sistema: $ICON_DIR/512x512/apps/com.example.media_downloader.png"
echo "    - Binario asociado: $BIN_PATH"
