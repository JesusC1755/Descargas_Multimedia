# ==============================================================================
# Multi-Stage Dockerfile para Media Downloader
# Diseñado para mínima huella de almacenamiento
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Compilación de Flutter Desktop (Builder)
# ------------------------------------------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

# 1. Instalar dependencias estrictamente necesarias para compilar Flutter Linux Desktop
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Descargar Flutter SDK (canal stable) y configurar el entorno
ARG FLUTTER_CHANNEL="stable"
RUN git clone --depth 1 -b ${FLUTTER_CHANNEL} https://github.com/flutter/flutter.git ${FLUTTER_HOME} && \
    flutter config --no-analytics --enable-linux-desktop && \
    flutter precache --linux

# 3. Descargar el binario standalone oficial de yt-dlp (evita instalar Python/pip en runner)
RUN curl -fsSL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux -o /usr/local/bin/yt-dlp && \
    chmod a+rx /usr/local/bin/yt-dlp

WORKDIR /app

# 4. Optimización de caché de capas Docker: resolver dependencias pub antes del código
COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

# 5. Copiar el código fuente y compilar el bundle Linux Desktop en modo Release
COPY . .
RUN flutter build linux --release

# ------------------------------------------------------------------------------
# Stage 2: Entorno Limpio de Ejecución (Runner)
# ------------------------------------------------------------------------------
FROM ubuntu:24.04 AS runner

ENV DEBIAN_FRONTEND=noninteractive

# Evitar que dpkg extraiga documentación, páginas man y traducciones innecesarias
RUN echo 'path-exclude=/usr/share/doc/*' > /etc/dpkg/dpkg.cfg.d/nodoc && \
    echo 'path-exclude=/usr/share/man/*' >> /etc/dpkg/dpkg.cfg.d/nodoc && \
    echo 'path-exclude=/usr/share/locale/*' >> /etc/dpkg/dpkg.cfg.d/nodoc && \
    echo 'path-exclude=/usr/share/info/*' >> /etc/dpkg/dpkg.cfg.d/nodoc

# 1. Instalar ÚNICAMENTE librerías dinámicas de ejecución y herramientas CLI necesarias:
#    - libgtk-3-0t64: Runtime GTK3 para la UI de Flutter (cero paquetes -dev)
#    - libgl1-mesa-dri: Aceleración gráfica por hardware (Mesa/OpenGL DRI)
#    - libpulse0: Soporte de audio PulseAudio
#    - ffmpeg: Transcodificación, muxing y análisis de códecs (incluye ffprobe)
#    - nodejs: Runtime EJS ligero para que yt-dlp resuelva firmas ofuscadas de YouTube
#    - ca-certificates: Certificados SSL para solicitudes HTTPS seguras
#    - xdg-utils: Integración con utilidades del escritorio (ej. abrir carpetas)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    ffmpeg \
    nodejs \
    libgtk-3-0t64 \
    libgl1-mesa-dri \
    libegl1 \
    libgles2 \
    libpulse0 \
    xdg-utils \
    zenity \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc/* /usr/share/man/* /usr/share/locale/*

# 2. Configurar usuario no-root con UID/GID parametrizables para sincronizar con el host
ARG USER_ID=1000
ARG GROUP_ID=1000

# Limpiar usuarios conflictivos preexistentes (como el usuario 'ubuntu' en Ubuntu 24.04)
RUN (id -u ${USER_ID} >/dev/null 2>&1 && userdel -r $(id -un ${USER_ID}) 2>/dev/null || true); \
    (getent group ${GROUP_ID} >/dev/null 2>&1 && groupdel $(getent group ${GROUP_ID} | cut -d: -f1) 2>/dev/null || true); \
    groupadd -g ${GROUP_ID} appuser && \
    useradd -u ${USER_ID} -g ${GROUP_ID} -m -s /bin/bash appuser && \
    usermod -aG video,render appuser 2>/dev/null || true && \
    mkdir -p /home/appuser/Descargas && \
    ln -s /home/appuser/Descargas /home/appuser/Downloads && \
    chown -R appuser:appuser /home/appuser

# 3. Copiar binario standalone de yt-dlp desde la etapa de compilación
COPY --from=builder /usr/local/bin/yt-dlp /usr/local/bin/yt-dlp

# 4. Copiar únicamente el bundle ejecutable compilado de Flutter
COPY --from=builder --chown=appuser:appuser /app/build/linux/x64/release/bundle /app

# 5. Configurar contexto de ejecución no-root
USER appuser
WORKDIR /app
ENV HOME=/home/appuser

# 6. Ejecutar la aplicación
ENTRYPOINT ["/app/media_downloader"]
