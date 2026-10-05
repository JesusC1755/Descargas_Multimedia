#!/usr/bin/env bash
# ==============================================================================
# Script de Ayuda para Lanzar Media Downloader en Docker
# Gestiona permisos temporales de X11, detección de rutas y ejecución en contenedor.
# ==============================================================================

set -euo pipefail

# Estilos y colores para terminal
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║       Media Downloader - Launcher Contenerizado      ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"

# 1. Resolver o crear la carpeta de descargas en el host
if [ -d "$HOME/Descargas" ]; then
    HOST_DOWNLOADS="$HOME/Descargas"
elif [ -d "$HOME/Downloads" ]; then
    HOST_DOWNLOADS="$HOME/Downloads"
else
    HOST_DOWNLOADS="$HOME/Descargas"
    echo -e "${YELLOW}[!] Creando carpeta de descargas en el host: ${HOST_DOWNLOADS}${NC}"
    mkdir -p "$HOST_DOWNLOADS"
fi
export HOST_DOWNLOADS_DIR="$HOST_DOWNLOADS"
echo -e "${GREEN}[✔] Carpeta de descargas:${NC} $HOST_DOWNLOADS_DIR"

# 2. Obtener UID y GID del usuario actual para garantizar permisos de archivo
export USER_ID="$(id -u)"
export GROUP_ID="$(id -g)"
echo -e "${GREEN}[✔] Permisos de usuario:${NC} UID=$USER_ID, GID=$GROUP_ID"

# 3. Validar variable DISPLAY
export DISPLAY="${DISPLAY:-:0}"
echo -e "${GREEN}[✔] Display gráfico:${NC} $DISPLAY"

# 4. Configurar permisos de X11 y trampa de limpieza al cerrar
if command -v xhost >/dev/null 2>&1; then
    echo -e "${BLUE}[*] Concediendo permisos locales temporales a X11 (xhost +local:docker)...${NC}"
    xhost +local:docker >/dev/null 2>&1 || true

    cleanup() {
        echo -e "\n${YELLOW}[*] Revocando permisos temporales de X11 (xhost -local:docker)...${NC}"
        xhost -local:docker >/dev/null 2>&1 || true
        echo -e "${GREEN}[✔] Limpieza completada. Aplicación finalizada.${NC}"
    }
    trap cleanup EXIT INT TERM
else
    echo -e "${YELLOW}[!] Advertencia: 'xhost' no está disponible. Si la ventana no abre, instala 'x11-xserver-utils'.${NC}"
fi

# 5. Compilar (si aplica) y levantar la aplicación
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${BLUE}[*] Iniciando contenedor con Docker Compose...${NC}"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up --build "$@"
