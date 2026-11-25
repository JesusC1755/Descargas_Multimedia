#!/usr/bin/env bash
# ==============================================================================
# build-arch-package.sh
# Genera el paquete de Arch Linux (.pkg.tar.zst) a partir del .tar.gz portable.
# Requiere haber ejecutado antes build-linux-bundle.sh (o usa --build para hacerlo).
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
VERSION=$(grep -E '^version:' "$PROJECT_ROOT/pubspec.yaml" | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
TARBALL="MediaDownloader-${VERSION}-Linux-x64-Portable.tar.gz"

if [ "${1:-}" = "--build" ]; then
    "$SCRIPT_DIR/build-linux-bundle.sh"
fi

if [ ! -f "$DIST_DIR/$TARBALL" ]; then
    echo "[-] No existe $DIST_DIR/$TARBALL. Ejecuta primero build-linux-bundle.sh (o usa --build)."
    exit 1
fi

STAGE="$DIST_DIR/arch"
rm -rf "$STAGE"
mkdir -p "$STAGE"
sed -E "s/^pkgver=.*/pkgver=$VERSION/" "$SCRIPT_DIR/arch/PKGBUILD" > "$STAGE/PKGBUILD"
cp "$DIST_DIR/$TARBALL" "$STAGE/"

echo "[*] Generando paquete de Arch Linux (versión $VERSION)..."
(cd "$STAGE" && PKGDEST="$DIST_DIR" makepkg --force --cleanbuild --nodeps)
rm -rf "$STAGE"

echo "[✔] Paquete generado:"
ls -lh "$DIST_DIR"/*.pkg.tar.zst
