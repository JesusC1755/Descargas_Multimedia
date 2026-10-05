#!/usr/bin/env bash
# ==============================================================================
# build-linux-bundle.sh
# Compila y empaqueta Media Downloader para Linux en formatos .deb y .tar.gz
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
BUNDLE_DIR="$PROJECT_ROOT/build/linux/x64/release/bundle"
LOCAL_CACHE="$PROJECT_ROOT/linux/tools"

SKIP_BUILD=false
VERSION=""

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            echo "Argumento desconocido: $1"
            echo "Uso: $0 [--skip-build] [--version X.Y.Z]"
            exit 1
            ;;
    esac
done

# Obtener versión desde pubspec.yaml si no fue proporcionada
if [ -z "$VERSION" ]; then
    VERSION=$(grep -E '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
fi

echo "===================================================="
echo "   Media Downloader - Empaquetador para Linux       "
echo "   Versión: $VERSION                                "
echo "===================================================="

# 1. Compilación de Flutter en modo Release (a menos que se indique --skip-build)
if [ "$SKIP_BUILD" = false ]; then
    echo ""
    echo "[*] Verificando dependencias de Flutter..."
    cd "$PROJECT_ROOT"
    flutter pub get

    echo "[*] Compilando aplicación Flutter para Linux (Release)..."
    flutter build linux --release
fi

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "[-] Error: No se encontró el directorio de release: $BUNDLE_DIR"
    exit 1
fi

mkdir -p "$DIST_DIR"
mkdir -p "$LOCAL_CACHE"

# 2. Asegurar binario de yt-dlp autónomo en tools/
TOOLS_DEST="$BUNDLE_DIR/tools"
mkdir -p "$TOOLS_DEST"

YTDLP_BIN="$LOCAL_CACHE/yt-dlp"
if [ ! -f "$YTDLP_BIN" ]; then
    echo "[*] Descargando binario oficial standalone de yt-dlp para Linux..."
    curl -fsSL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" -o "$YTDLP_BIN"
    chmod +x "$YTDLP_BIN"
fi
cp "$YTDLP_BIN" "$TOOLS_DEST/yt-dlp"
chmod +x "$TOOLS_DEST/yt-dlp"
echo "[+] Binario yt-dlp sincronizado en tools/."

# 3. Generar paquete Portable .tar.gz
TAR_NAME="MediaDownloader-Linux-x64-Portable.tar.gz"
TAR_OUTPUT="$DIST_DIR/$TAR_NAME"
STAGE_PORTABLE="$DIST_DIR/media-downloader-linux-x64"

echo ""
echo "[*] Generando paquete portable .tar.gz..."
rm -rf "$STAGE_PORTABLE" "$TAR_OUTPUT"
mkdir -p "$STAGE_PORTABLE"

# Copiar bundle completo a la carpeta portable
cp -a "$BUNDLE_DIR/." "$STAGE_PORTABLE/"

# Crear launcher amigable run.sh
cat << 'EOF' > "$STAGE_PORTABLE/run.sh"
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/media_downloader" "$@"
EOF
chmod +x "$STAGE_PORTABLE/run.sh"

tar -czf "$TAR_OUTPUT" -C "$DIST_DIR" "media-downloader-linux-x64"
rm -rf "$STAGE_PORTABLE"
echo "[✔] Paquete portable generado: $TAR_OUTPUT ($(du -h "$TAR_OUTPUT" | cut -f1))"

# 4. Generar paquete nativo .deb (Debian / Ubuntu / Linux Mint)
DEB_PACKAGE_NAME="media-downloader"
DEB_FILE_NAME="${DEB_PACKAGE_NAME}_${VERSION}_amd64.deb"
DEB_OUTPUT="$DIST_DIR/$DEB_FILE_NAME"
STAGE_DEB="$DIST_DIR/pkg_deb/${DEB_PACKAGE_NAME}_${VERSION}_amd64"

echo ""
echo "[*] Generando paquete Debian (.deb)..."
rm -rf "$STAGE_DEB" "$DEB_OUTPUT"

# Estructura del paquete .deb
mkdir -p "$STAGE_DEB/DEBIAN"
mkdir -p "$STAGE_DEB/opt/media-downloader"
mkdir -p "$STAGE_DEB/usr/bin"
mkdir -p "$STAGE_DEB/usr/share/applications"
mkdir -p "$STAGE_DEB/usr/share/icons/hicolor/32x32/apps"
mkdir -p "$STAGE_DEB/usr/share/icons/hicolor/64x64/apps"
mkdir -p "$STAGE_DEB/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$STAGE_DEB/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$STAGE_DEB/usr/share/icons/hicolor/512x512/apps"

# Copiar bundle a /opt/media-downloader
cp -a "$BUNDLE_DIR/." "$STAGE_DEB/opt/media-downloader/"

# Wrapper ejecutable en /usr/bin
cat << 'EOF' > "$STAGE_DEB/usr/bin/media_downloader"
#!/usr/bin/env bash
exec /opt/media-downloader/media_downloader "$@"
EOF
chmod 755 "$STAGE_DEB/usr/bin/media_downloader"

# Acceso directo .desktop
cat << 'EOF' > "$STAGE_DEB/usr/share/applications/com.example.media_downloader.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Media Downloader
Comment=Descargas de Audio y Video con yt-dlp y FFmpeg
Exec=/usr/bin/media_downloader %u
Icon=com.example.media_downloader
Terminal=false
Categories=AudioVideo;Audio;Video;Network;
StartupWMClass=com.example.media_downloader
Keywords=youtube;downloader;video;audio;mp3;mp4;
EOF
chmod 644 "$STAGE_DEB/usr/share/applications/com.example.media_downloader.desktop"

# Copiar iconos en todas las resoluciones
ICONS_SRC="$PROJECT_ROOT/assets/icons"
if [ -d "$ICONS_SRC" ]; then
    [ -f "$ICONS_SRC/app_icon_32.png" ]  && cp "$ICONS_SRC/app_icon_32.png"  "$STAGE_DEB/usr/share/icons/hicolor/32x32/apps/com.example.media_downloader.png"
    [ -f "$ICONS_SRC/app_icon_64.png" ]  && cp "$ICONS_SRC/app_icon_64.png"  "$STAGE_DEB/usr/share/icons/hicolor/64x64/apps/com.example.media_downloader.png"
    [ -f "$ICONS_SRC/app_icon_128.png" ] && cp "$ICONS_SRC/app_icon_128.png" "$STAGE_DEB/usr/share/icons/hicolor/128x128/apps/com.example.media_downloader.png"
    [ -f "$ICONS_SRC/app_icon_256.png" ] && cp "$ICONS_SRC/app_icon_256.png" "$STAGE_DEB/usr/share/icons/hicolor/256x256/apps/com.example.media_downloader.png"
    [ -f "$ICONS_SRC/app_icon.png" ]     && cp "$ICONS_SRC/app_icon.png"     "$STAGE_DEB/usr/share/icons/hicolor/512x512/apps/com.example.media_downloader.png"
fi

# Archivo de control de Debian
cat << EOF > "$STAGE_DEB/DEBIAN/control"
Package: $DEB_PACKAGE_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Media Downloader Developers
Depends: libc6, libgtk-3-0 (>= 3.24.0), ffmpeg
Recommends: nodejs
Description: Media Downloader for Linux Desktop
 Interfaz gráfica moderna en Flutter para descargas multimedia de audio y video
 utilizando yt-dlp y FFmpeg.
EOF

# Scripts de post-instalación y post-remoción para actualizar cache de iconos y escritorio
cat << 'EOF' > "$STAGE_DEB/DEBIAN/postinst"
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -f -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF
chmod 755 "$STAGE_DEB/DEBIAN/postinst"

cat << 'EOF' > "$STAGE_DEB/DEBIAN/postrm"
#!/bin/sh
set -e
if [ -x /usr/bin/update-desktop-database ]; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if [ -x /usr/bin/gtk-update-icon-cache ]; then
    gtk-update-icon-cache -f -q /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi
EOF
chmod 755 "$STAGE_DEB/DEBIAN/postrm"

# Compilar el archivo .deb
dpkg-deb --build --root-owner-group "$STAGE_DEB" "$DEB_OUTPUT"
rm -rf "$DIST_DIR/pkg_deb"
echo "[✔] Paquete .deb generado: $DEB_OUTPUT ($(du -h "$DEB_OUTPUT" | cut -f1))"

echo ""
echo "===================================================="
echo "   Empaquetado completado con éxito!                "
echo "===================================================="
echo "Archivos generados en $DIST_DIR:"
ls -lh "$DIST_DIR"
