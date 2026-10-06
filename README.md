# 🎬 Media Downloader (Desktop & Multiplatform)

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Material 3](https://img.shields.io/badge/Material_3-DeepBlue-6750A4?logo=materialdesign&logoColor=white)
![Canvas GPU](https://img.shields.io/badge/Canvas-CustomPainter_60FPS-FF6F00?logo=webgl&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Multi--Stage_<300MB-2496ED?logo=docker&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Ubuntu_%7C_Debian-FCC624?logo=linux&logoColor=black)


**Aplicación de escritorio y multiplataforma moderna, reactiva y elegante para la extracción, conversión y descarga de video y audio con arquitectura desacoplada y topología 100% local (Zero-Server).**

[Características](#-características-principales) • [Arquitectura](#-arquitectura-del-sistema) • [Stack Tecnológico](#-stack-tecnológico-y-herramientas) • [Canvas y UI](#-canvas-y-experiencia-visual-de-usuario) • [Dockerización](#-estrategia-de-dockerización-y-ejecución-aislada) • [Distribución Nativa](#-distribución-y-empaquetado-nativo-linux) • [Guía de Desarrollo](#-instalación-y-desarrollo-local)

</div>

---

## 🌟 Características Principales

* 🔒 **Topología 100% Local (Zero-Server):** Sin servidores intermediarios, proxies de terceros ni costos de nube. Todas las peticiones salen de la conexión directa del dispositivo, previniendo bloqueos por IP de datacenters (HTTP 429 / Cloudflare / captchas).
* 🎯 **Compatibilidad Multiplataforma:** Soporte para YouTube, TikTok, Instagram Reels, X (Twitter), Facebook, Twitch VODs, Reddit, Vimeo y enlaces directos de video.
* 🎛️ **Control Granular de Calidad y Formato:**
  * **Video (MP4):** Resoluciones desde 360p hasta 4K UHD y 60 FPS, priorizando códecs universales (`H.264 / AVC1` + `AAC`) para reproducción garantizada en VLC, reproductores de escritorio, navegadores y Smart TVs.
  * **Solo Audio:** Extracción dedicada a contenedores y códecs de alta fidelidad (`MP3` a 320 kbps, `FLAC`, `M4A/AAC`, `Opus`).
* ⚡ **Streaming Reactivo en Tiempo Real:** Barra de progreso fluida con porcentaje exacto, velocidad de transferencia (`MB/s`), tiempo estimado de finalización (`ETA`) y etapa de multiplexación (`muxing` con FFmpeg).
* 🛡️ **Validación y Sanitización Robusta:** Detección de URLs maliciosas o malformadas, eliminación de parámetros espía de seguimiento (`utm_*`, `si=`, `fbclid`) antes de invocar subprocesos.
* 📋 **Integración de Escritorio:** Pegado directo desde el portapapeles con un clic (`Ctrl + V`), atajo de teclado global para iniciar análisis (`Enter`) y apertura directa de la carpeta de descargas del sistema.
* 📊 **Observabilidad y Depuración Integrada:** Monitor de logs en memoria en tiempo real potenciado por **Talker**, con visor interactivo de excepciones y botón para copiar diagnósticos al portapapeles.

---

## 🏗️ Arquitectura del Sistema

El proyecto implementa los principios de **Clean Architecture** y el patrón **Hexagonal (Ports & Adapters)**, asegurando que la lógica de negocio permanezca pura, testeable y totalmente independiente del sistema operativo o motor CLI subyacente.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Capa de Presentación (UI)                      │
│        Material 3 • Canvas Dual-Track Painter • Tarjetas Reactivas     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ consume Streams y Notificaciones
┌───────────────────────────────────▼────────────────────────────────────┐
│                    Capa de Dominio (Pure Dart Core)                    │
│   Modelos Inmutables: MediaInfo, DownloadProgress, StreamOption        │
│   Contrato / Puerto: IMediaEngine (media_engine_port.dart)             │
└───────────────────────┬───────────────────────────────┬────────────────┘
                        │ implementa contrato           │
       ┌────────────────▼──────────────┐ ┌──────────────▼──────────────┐
       │     Infrastructure (Desktop)  │ │   Infrastructure (Android)  │
       │   DesktopProcessEngine        │ │   AndroidNativeEngine       │
       │   • Subprocesos dart:io       │ │   (Planificado: Chaquopy +  │
       │   • Pipes async yt-dlp        │ │    FFmpeg-Kit JNI)          │
       │   • Muxing FFmpeg             │ │                             │
       │   • Node.js EJS Runtime       │ │                             │
       └───────────────────────────────┘ └─────────────────────────────┘
```

### Flujo de Datos Reactivo

1. **Captura y Sanitización:** `UrlInputCard` recibe la URL y la valida contra `MediaUrlValidator`, descartando protocolos inseguros y limpiando hashes de tracking.
2. **Extracción de Metadatos:** `HomeScreen` delega a `DesktopProcessEngine.analyzeUrl()`, que invoca `yt-dlp --dump-json --js-runtimes node <url>` y genera un modelo inmutable `MediaInfo`.
3. **Selección y Configuración:** El usuario elige la resolución o códec en `QualitySelectorCard`.
4. **Pipeline de Descarga Asíncrono:** `DesktopProcessEngine.download()` lanza el subproceso combinando las pistas de audio y video con FFmpeg y expone un `Stream<DownloadProgress>`.
5. **Renderizado en UI:** `DownloadProgressCard` escucha el `Stream` y actualiza reactivamente la barra de progreso, la velocidad y las métricas de tiempo sin bloquear el hilo principal.

---

## 🛠️ Stack Tecnológico y Herramientas

| Componente | Tecnología | Justificación y Rol en el Proyecto |
| :--- | :--- | :--- |
| **Framework Base** | **Flutter 3.x / Dart 3.x** | Compilación a código nativo de alto rendimiento (60+ FPS en Linux Desktop) sin la sobrecarga de memoria de Electron/Chromium. |
| **Sistema de Diseño** | **Material 3 (M3)** | Lenguaje visual moderno con `SegmentedButton`, chips dinámicos, `FilledButton`, superficies tonales y bordes suaves (16px). |
| **Theming Dinámico** | **FlexColorScheme (`deepBlue`)** | Paleta cromática profunda de alto contraste, diseñada específicamente para entornos oscuros de escritorio y legibilidad técnica. |
| **Motor Gráfico** | **Canvas API & CustomPainter** | Renderizado gráfico por GPU de un fondo ambiental animado con flujos paralelos de video y audio. |
| **Motor de Extracción** | **`yt-dlp` (Standalone)** | Extractor líder de la industria, actualizado permanentemente contra cambios en los tokens de firma (`n-sig`) de las plataformas. |
| **Motor Multimedia** | **`FFmpeg` + `ffprobe`** | Mezcla (multiplexado) sin pérdida de calidad (`-c copy`) de pistas de video DASH y streams de audio, además de transcodificación a MP3. |
| **Resolución JavaScript** | **`Node.js` (EJS Runtime)** | Runtime ligero inyectado a `yt-dlp` vía `--js-runtimes node` para interpretar algoritmos de firma JavaScript ofuscados de YouTube. |
| **Logging y Diagnóstico**| **`talker_flutter`** | Sistema de observabilidad centralizado que captura eventos de ciclo de vida, excepciones en zona segura (`runZonedGuarded`) y errores de subprocesos. |
| **Aislamiento / Deploy** | **Docker Multi-Stage** | Empaquetado minimalista (< 300 MB) con aceleración gráfica por hardware Mesa DRI (`/dev/dri`) y servidor gráfico X11. |

---

## 🎨 Canvas y Experiencia Visual de Usuario

A diferencia de interfaces estáticas convencionales, Media Downloader incorpora un fondo dinámico de alto impacto estético desarrollado sobre el **Canvas nativo de Flutter** mediante `CustomPainter`:

### `AmbientMeshBackground` (`lib/presentation/widgets/ambient_mesh_background.dart`)
* **Pipeline Gráfico GPU:** Renderizado en un `RepaintBoundary` alimentado por un `AnimationController` continuo a 60 FPS, garantizando que las animaciones matemáticas no provoquen repintados innecesarios del árbol de widgets interactivo.
* **Dual Track Stream Visualizer:**
  * **Pista Izquierda (Pipeline Video MP4):** Haces descendentes en tonos **Cian Neón (`#38BDF8` / `#06B6D4`)** con partículas y micro-etiquetas tipográficas (`4K UHD`, `1080p`, `60 FPS`, `AV1`, `H.264`).
  * **Pista Derecha (Pipeline Audio Master):** Haces en degradado **Fucsia/Rosa Neón (`#FB7185` / `#E11D48`)** con micro-etiquetas (`320 kbps`, `FLAC`, `48 kHz`, `STEREO`, `MP3`).
  * **Fondo Profundo:** Base oscura (`#08080D`) con halos de luz radial cenital (`RadialGradient`) que elevan el contraste y realzan las tarjetas translúcidas de la interfaz.

---

## 🐳 Estrategia de Dockerización y Ejecución Aislada

 Ofrece una solución de contenedorización que permite ejecutar la aplicación en cualquier distribución Linux **sin requerir Flutter SDK, Git, Clang, CMake, Python ni Node.js en el sistema anfitrión**.

### 1. Optimización Multi-Stage (< 300 MB)
Las imágenes tradicionales de Flutter Desktop suelen pesar entre 3 GB y 5 GB al arrastrar compiladores y herramientas de desarrollo. Este contenedor reduce la huella a **~295 MB**:
* **Stage 1 (Builder - `ubuntu:24.04`):** Clona Flutter stable, descarga dependencias (`flutter pub get`), compila el bundle estático en release y extrae el binario standalone de `yt-dlp`. Todo este entorno pesado es **descartado al 100%**.
* **Stage 2 (Runner - `ubuntu:24.04`):** Base limpia que instala exclusivamente librerías dinámicas de ejecución (`libgtk-3-0t64`, `libgl1-mesa-dri`, `libegl1`, `libgles2`, `libpulse0`, `ffmpeg`, `nodejs`). Suprime manuales y cachés de paquetes (`/etc/dpkg/dpkg.cfg.d/nodoc`).

### 2. Aceleración Gráfica GPU y Servidor X11
* **Dispositivos `/dev/dri`:** Renderizado nativo por GPU (Intel, AMD, NVIDIA con drivers Mesa DRI).
* **Socket X11:** Mapeo de `/tmp/.X11-unix` y variable `DISPLAY` para proyectar la ventana de Flutter directamente en el escritorio del usuario.
* **Modo Host (`network_mode: host` / `ipc: host`):** Latencia cero en la comunicación con el servidor gráfico y resolución de red idéntica al host.

### 3. Seguridad y Permisos No-Root
El contenedor ejecuta como `appuser`, cuyos `UID` y `GID` se sincronizan automáticamente con el usuario actual del host (`id -u` / `id -g`). Esto asegura que los archivos descargados en la carpeta montada `~/Descargas` queden con la propiedad correcta y nunca bloqueados por `root`.

### 4. Cómo Ejecutar con Docker

```bash
# Opción 1: Lanzador automatizado (Gestiona permisos xhost y lanza el contenedor)
./docker/run-docker.sh

# Opción 2: Ejecución en segundo plano (detached)
./docker/run-docker.sh -d

# Opción 3: Vía Docker Compose directamente
docker compose -f docker/docker-compose.yml up --build
```

---

## 📦 Distribución y Empaquetado Nativo (Linux)

El módulo [`linux/packaging/`] permite generar paquetes nativos instalables o portables para distribución masiva:

### Artefactos Generados (`dist/`)
1. **Paquete Debian (`.deb`):** `media-downloader_<version>_amd64.deb`
   * Instala la aplicación en `/opt/media-downloader/`.
   * Enlaza el binario en `/usr/bin/media_downloader`.
   * Registra el icono de alta resolución y el archivo `.desktop` en el menú del sistema.
   * Instalación:
     ```bash
     sudo dpkg -i dist/media-downloader_*_amd64.deb
     ```
2. **Paquete Portable (`.tar.gz`):** `MediaDownloader-Linux-x64-Portable.tar.gz`
   * Compatible con Arch Linux, Fedora, openSUSE, etc.
   * No requiere permisos `sudo`.
   * Incluye el lanzador `run.sh`:
     ```bash
     tar -xzf MediaDownloader-Linux-x64-Portable.tar.gz
     cd media-downloader-linux-x64
     ./run.sh
     ```

### Compilación Local del Bundle
```bash
# Compilar Flutter y empaquetar ambos formatos
./linux/packaging/build-linux-bundle.sh

# Reempaquetar sin recompilar Flutter
./linux/packaging/build-linux-bundle.sh --skip-build
```


## 💻 Instalación y Desarrollo Local

### Prerrequisitos en el Host
Si deseas compilar y ejecutar el proyecto localmente sin Docker:
* **Flutter SDK:** Canal stable (>= 3.3.0).
* **Herramientas de compilación C++:** `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`.
* **Herramientas de procesamiento:**
  * `yt-dlp` (>= 2026.08) ubicado en `~/.local/bin/yt-dlp` o en `$PATH`.
  * `ffmpeg` instalado en el sistema (`sudo apt install ffmpeg`).
  * `node` instalado o enlazado en `~/.local/bin/node` (para resolución de firmas JS).

### Pasos de Ejecución

```bash
# 1. Clonar el repositorio
git clone https://github.com/JesusC1755/Descargas_Multimedia.git
cd Descargas_Multimedia

# 2. Obtener dependencias de Dart/Flutter
flutter pub get

# 3. Ejecutar suite de pruebas unitarias
flutter test

# 4. Lanzar la aplicación en modo desarrollo
flutter run -d linux

# 5. Compilar bundle de producción
flutter build linux --release
```

---

## 📁 Estructura del Código Fuente

```text
lib/
├── core/                                    # Utilidades transversales y configuración global
│   ├── logging/
│   │   └── app_logger.dart                  # Instancia global de Talker para observabilidad
│   ├── theme/
│   │   └── app_theme.dart                   # Sistema de diseño Material 3 con FlexColorScheme
│   └── utils/
│       ├── formatters.dart                  # Formateo de bytes, duraciones y velocidades
│       └── media_url_validator.dart         # Sanitización y validación estricta de URLs
│
├── domain/                                  # Capa de Dominio (Dart puro, agnóstico al SO)
│   ├── models/
│   │   ├── download_progress.dart           # Estado inmutable del avance (% avance, KB/s, ETA)
│   │   ├── media_info.dart                  # Metadatos del contenido (título, duración, formatos)
│   │   └── stream_option.dart               # Opciones seleccionables de video y audio
│   └── ports/
│       └── media_engine_port.dart           # Interfaz abstracta IMediaEngine
│
├── infrastructure/                          # Capa de Infraestructura (Adaptadores)
│   └── desktop/
│       └── desktop_process_engine.dart      # Motor CLI: subprocesos yt-dlp + FFmpeg + Node.js
│
├── presentation/                            # Capa de Presentación (Flutter UI)
│   ├── screens/
│   │   └── home_screen.dart                 # Pantalla principal y orquestador del estado
│   └── widgets/
│       ├── ambient_mesh_background.dart     # Fondo animado CustomPainter (Canvas GPU)
│       ├── download_progress_card.dart      # Monitor de descarga activa y visor de errores
│       ├── media_preview_card.dart          # Tarjeta con miniatura y metadatos del autor
│       ├── quality_selector_card.dart       # Selector de resolución y códecs de audio
│       └── url_input_card.dart              # Campo de texto para URL con pegado inteligente
│
└── main.dart                                # Punto de entrada y captura de errores en zona segura
```

---
