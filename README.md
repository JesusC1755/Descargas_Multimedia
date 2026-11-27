# 🎬 Media Downloader (Desktop & Multiplatform)

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Material 3](https://img.shields.io/badge/Material_3-DeepBlue-6750A4?logo=materialdesign&logoColor=white)
![Canvas GPU](https://img.shields.io/badge/Canvas-CustomPainter_60FPS-FF6F00?logo=webgl&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Multi--Stage_<300MB-2496ED?logo=docker&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Arch_%7C_Portable-FCC624?logo=linux&logoColor=black)


**Aplicación de escritorio y multiplataforma moderna, reactiva y elegante para la extracción, conversión y descarga de video y audio con arquitectura desacoplada y topología 100% local (Zero-Server).**

[Características](#-características-principales) • [Arquitectura](#-arquitectura-del-sistema) • [Stack Tecnológico](#-stack-tecnológico-y-herramientas) • [Android](#-android) • [Canvas y UI](#-canvas-y-experiencia-visual-de-usuario) • [Dockerización](#-estrategia-de-dockerización-y-ejecución-aislada) • [Distribución Nativa](#-distribución-y-empaquetado-nativo-linux) • [Guía de Desarrollo](#-instalación-y-desarrollo-local)

</div>

---

## 🌟 Características Principales

* 🔒 **Topología 100% Local (Zero-Server):** Sin servidores intermediarios, proxies de terceros ni costos de nube. Todas las peticiones salen de la conexión directa del dispositivo, previniendo bloqueos por IP de datacenters (HTTP 429 / Cloudflare / captchas).
* 🎯 **Compatibilidad Multiplataforma:** Soporte para YouTube, TikTok, Instagram Reels, X (Twitter), Facebook, Twitch VODs, Reddit, Vimeo y enlaces directos de video.
* 🎛️ **Control Granular de Calidad y Formato:**
  * **Video (MP4):** Resoluciones hasta 1080p (Full HD) en `H.264 / AVC1` + `AAC`, descargadas sin recodificar, para reproducción garantizada en VLC, reproductores de escritorio, navegadores y Smart TVs.
  * **Solo Audio:** Extracción dedicada a contenedores y códecs de alta fidelidad (`MP3` a 320 kbps, `FLAC`, `M4A/AAC`, `Opus`).
* ⚡ **Streaming Reactivo en Tiempo Real:** Barra de progreso fluida con porcentaje exacto, velocidad de transferencia (`MB/s`), tiempo estimado de finalización (`ETA`) y etapa de multiplexación (`muxing` con FFmpeg).
* 🛡️ **Validación y Sanitización Robusta:** Detección de URLs maliciosas o malformadas, eliminación de parámetros espía de seguimiento (`utm_*`, `si=`, `fbclid`) antes de invocar subprocesos.
* 📱 **Android:** APK de 28 MB, YouTube sin yt-dlp, descargas en segundo plano con notificación y guardado en cualquier carpeta (incluida la tarjeta SD) vía MediaStore/SAF.
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
       │   • YouTube directo (Dart)    │ │   • YouTube directo (Kotlin)│
       │   • Subprocesos dart:io       │ │   • MethodChannel/EventCh.  │
       │   • Pipes async yt-dlp        │ │   • youtubedl-android       │
       │   • Muxing FFmpeg             │ │     (yt-dlp + QuickJS)      │
       │   • Node.js EJS Runtime       │ │   • MediaTools (sin FFmpeg) │
       │                               │ │   • DownloadService         │
       │                               │ │   • MediaStore / SAF        │
       └───────────────────────────────┘ └─────────────────────────────┘
```

### Flujo de Datos Reactivo

1. **Captura y Sanitización:** `UrlInputCard` recibe la URL y la valida contra `MediaUrlValidator`, descartando protocolos inseguros y limpiando hashes de tracking.
2. **Extracción de Metadatos:** `HomeScreen` delega a `DesktopProcessEngine.analyzeUrl()`. Con YouTube, `YouTubeDirectClient` hace una sola petición al API de YouTube (< 1 s); con el resto de sitios, o si eso falla, se invoca `yt-dlp --dump-json --js-runtimes node <url>`. En ambos casos el resultado tiene la forma del JSON de yt-dlp y se convierte en un modelo inmutable `MediaInfo`.
3. **Selección y Configuración:** El usuario elige la resolución o códec en `QualitySelectorCard`.
4. **Pipeline de Descarga Asíncrono:** `DesktopProcessEngine.download()` descarga YouTube por HTTP directo (bloques de 10 MB, 4 conexiones) y el resto con yt-dlp; FFmpeg une las pistas o convierte el audio. El avance se expone como `Stream<DownloadProgress>`.
5. **Renderizado en UI:** `DownloadProgressCard` escucha el `Stream` y actualiza reactivamente la barra de progreso, la velocidad y las métricas de tiempo sin bloquear el hilo principal.

---

## 🛠️ Stack Tecnológico y Herramientas

| Componente | Tecnología | Justificación y Rol en el Proyecto |
| :--- | :--- | :--- |
| **Framework Base** | **Flutter 3.x / Dart 3.x** | Compilación a código nativo de alto rendimiento (60+ FPS en Linux Desktop) sin la sobrecarga de memoria de Electron/Chromium. |
| **Sistema de Diseño** | **Material 3 (M3)** | Lenguaje visual moderno con `SegmentedButton`, chips dinámicos, `FilledButton`, superficies tonales y bordes suaves (16px). |
| **Theming Dinámico** | **FlexColorScheme (`deepBlue`)** | Paleta cromática profunda de alto contraste, diseñada específicamente para entornos oscuros de escritorio y legibilidad técnica. |
| **Motor Gráfico** | **Canvas API & CustomPainter** | Renderizado gráfico por GPU de un fondo ambiental animado con flujos paralelos de video y audio. |
| **YouTube directo** | **Cliente `ios_producer` propio** | Una petición al API interno de YouTube (`/youtubei/v1/player`) que devuelve URLs directas en H.264 + AAC, sin desafío JS: analiza en < 1 s. Implementado en Dart (escritorio) y Kotlin (Android); yt-dlp queda como respaldo. |
| **Motor de Extracción** | **`yt-dlp` (Standalone)** | Extractor líder de la industria para el resto de sitios, actualizado permanentemente contra cambios en los tokens de firma (`n-sig`) de las plataformas. |
| **Motor Multimedia (escritorio)** | **`FFmpeg` + `ffprobe`** | Mezcla (multiplexado) sin pérdida de calidad (`-c copy`) de pistas de video DASH y streams de audio, además de transcodificación a MP3. |
| **Resolución JavaScript** | **`Node.js` (EJS Runtime)** | Runtime ligero inyectado a `yt-dlp` vía `--js-runtimes node` para interpretar algoritmos de firma JavaScript ofuscados de YouTube. |
| **Motor Android** | **`youtubedl-android`** | yt-dlp y QuickJS empaquetados para Android, invocados desde Kotlin vía MethodChannel. |
| **Multimedia Android** | **MediaMuxer / MediaCodec + LAME** | Une pistas y convierte audio con las APIs de Android en lugar de FFmpeg (35 MB menos). MP3 con LAME 3.100, compilado con el NDK. |
| **Preferencias** | **`shared_preferences`** | Recuerda la carpeta de destino entre sesiones. |
| **Logging y Diagnóstico**| **`talker_flutter`** | Sistema de observabilidad centralizado que captura eventos de ciclo de vida, excepciones en zona segura (`runZonedGuarded`) y errores de subprocesos. |
| **Aislamiento / Deploy** | **Docker Multi-Stage** | Empaquetado minimalista (< 300 MB) con aceleración gráfica por hardware Mesa DRI (`/dev/dri`) y servidor gráfico X11. |

---

## 📱 Android

La app usa el mismo dominio y la misma UI; solo cambia el adaptador (`AndroidNativeEngine` + código Kotlin en `android/app/src/main/kotlin/`).

* **YouTube sin yt-dlp:** `YouTubeFastExtractor` hace una sola petición al API de YouTube con el cliente `ios_producer` (el mismo que usa yt-dlp), que entrega URLs directas sin desafío JavaScript y funciona con música con licencia. `DirectDownloader` baja vídeo y audio en paralelo, en bloques de 10 MB con 4 conexiones. Si algo falla, se reintenta con yt-dlp.
* **Resto de sitios:** [`youtubedl-android`](https://github.com/JunkFood02/youtubedl-android) ejecuta yt-dlp con Python embebido y QuickJS. yt-dlp se actualiza en segundo plano como máximo una vez cada 24 h. A igual resolución se prefiere HTTPS sobre HLS.
* **Sin FFmpeg (APK de 28 MB):** yt-dlp deja vídeo y audio en archivos separados y `MediaTools` los une con MediaMuxer, sin recodificar. El audio se convierte con MediaCodec (M4A, Opus, FLAC) y LAME (MP3). LAME se descarga y compila con CMake en la primera compilación (`android/app/src/main/cpp/`).
* **Calidades:** solo H.264 hasta 1080p, para no recodificar VP9/AV1 en el teléfono.
* **Descarga sin repetir el análisis:** el JSON del análisis se reutiliza (vigencia 3 h); con yt-dlp, mediante `--load-info-json`.
* **Almacenamiento (scoped storage):** yt-dlp descarga en una carpeta privada de la app y luego el archivo se exporta:
  * carpeta predeterminada → `Download/` mediante MediaStore;
  * carpeta elegida por el usuario (incluida la SD) → SAF con permiso persistente.
* **Segundo plano:** `DownloadService` (servicio en primer plano `dataSync`) muestra el progreso en una notificación con botón *Cancelar*; al volver a abrir la app se recupera el progreso.

### Compilar e instalar
Requiere el NDK y CMake 3.22.1 del SDK de Android (para LAME). La primera compilación necesita internet para descargar LAME.
```bash
flutter build apk --debug                 # o --release
adb devices                               # si aparece dos veces el mismo teléfono, usa -s
adb -s <IP:puerto> install -r build/app/outputs/flutter-apk/app-debug.apk
```
La release se firma con la clave indicada en `android/key.properties` (no se sube a git); sin ese archivo se firma con la clave de depuración. Para publicar una versión nueva, sube `version:` en `pubspec.yaml` (el número tras `+` siempre creciente) y firma siempre con la misma clave.

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
* **Stage 1 (Builder - `ubuntu:24.04`):** Clona Flutter stable, descarga dependencias (`flutter pub get`), compila el bundle estático en release y descarga la última versión del binario standalone de `yt-dlp` (en cada construcción se comprueba si salió una nueva). Todo este entorno pesado es **descartado al 100%**.
* **Stage 2 (Runner - `ubuntu:24.04`):** Base limpia que instala exclusivamente librerías dinámicas de ejecución (`libgtk-3-0t64`, `libgl1-mesa-dri`, `libegl1`, `libgles2`, `libpulse0`, `ffmpeg`, `nodejs`). Suprime manuales y cachés de paquetes (`/etc/dpkg/dpkg.cfg.d/nodoc`). `yt-dlp` se copia a `~/.local/bin` del usuario del contenedor y con su propiedad, para que la app lo actualice sola cada 24 h.

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
1. **Paquete Portable (`.tar.gz`):** `MediaDownloader-<version>-Linux-x64-Portable.tar.gz`
   * Cualquier distribución de 64 bits; no requiere `sudo`.
   * Incluye yt-dlp en `tools/` (la app lo actualiza sola) y el lanzador `run.sh`. Necesita FFmpeg en el sistema.
     ```bash
     tar -xzf MediaDownloader-<version>-Linux-x64-Portable.tar.gz
     ./media-downloader-linux-x64/run.sh
     ```
2. **Paquete de Arch Linux (`.pkg.tar.zst`):** `media-downloader-bin-<version>-1-x86_64.pkg.tar.zst`
   * Arch y derivadas (CachyOS, Manjaro, EndeavourOS…). Depende de `gtk3`, `ffmpeg` y `yt-dlp`.
     ```bash
     sudo pacman -U media-downloader-bin-*-x86_64.pkg.tar.zst
     ```
3. **Paquete Debian (`.deb`):** `media-downloader_<version>_amd64.deb`, solo si `dpkg-deb` está instalado.
   * Instala la aplicación en `/opt/media-downloader/` y la registra en el menú del sistema.

### Compilación Local
```bash
# Compilar Flutter, el .tar.gz portable (y el .deb si hay dpkg-deb) y el paquete de Arch
./linux/packaging/build-arch-package.sh --build

# Solo el bundle portable / reempaquetar sin recompilar Flutter
./linux/packaging/build-linux-bundle.sh
./linux/packaging/build-linux-bundle.sh --skip-build
```

### Publicar una versión
Los archivos de cada release se reúnen en `dist/v<version>/` (APK, `.tar.gz`, paquete de Arch, `SHA256SUMS.txt` y las notas) y se suben a GitHub Releases con la etiqueta `v<version>`.


## 💻 Instalación y Desarrollo Local

### Prerrequisitos en el Host
Si deseas compilar y ejecutar el proyecto localmente sin Docker:
* **Flutter SDK:** Canal stable (>= 3.3.0).
* **Herramientas de compilación C++:** `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`.
* **Herramientas de procesamiento:**
  * `yt-dlp` (>= 2026.08) ubicado en `~/.local/bin/yt-dlp` o en `$PATH`. La app lo actualiza sola (`yt-dlp -U`) como máximo una vez cada 24 h; para eso conviene el binario oficial en `~/.local/bin`, ya que instalado con pacman/pip se actualiza con el gestor de paquetes.
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
│   │   ├── download_destination.dart        # Carpeta de destino (ruta visible + URI SAF en Android)
│   │   ├── download_progress.dart           # Estado inmutable del avance (% avance, KB/s, ETA)
│   │   ├── media_info.dart                  # Metadatos del contenido (título, duración, formatos)
│   │   └── stream_option.dart               # Opciones seleccionables de video y audio
│   └── ports/
│       └── media_engine_port.dart           # Interfaz abstracta IMediaEngine
│
├── infrastructure/                          # Capa de Infraestructura (Adaptadores)
│   ├── android/
│   │   └── android_native_engine.dart       # Puente con el motor nativo (MethodChannel/EventChannel)
│   ├── desktop/
│   │   └── desktop_process_engine.dart      # Motor CLI: subprocesos yt-dlp + FFmpeg + Node.js
│   ├── youtube/
│   │   └── youtube_direct.dart              # YouTube sin yt-dlp: API ios_producer + descarga HTTP por bloques
│   └── media_engine_factory.dart            # Elige el motor según la plataforma
│
├── presentation/                            # Capa de Presentación (Flutter UI)
│   ├── screens/
│   │   └── home_screen.dart                 # Pantalla principal y orquestador del estado
│   └── widgets/
│       ├── ambient_mesh_background.dart     # Fondo animado CustomPainter (Canvas GPU)
│       ├── download_progress_card.dart      # Monitor de descarga activa y visor de errores
│       ├── media_preview_card.dart          # Tarjeta con miniatura y metadatos del autor
│       ├── media_preview_skeleton.dart      # Esqueleto de carga durante el análisis
│       ├── quality_selector_card.dart       # Selector de resolución y códecs de audio
│       └── url_input_card.dart              # Campo de texto para URL con pegado inteligente
│
└── main.dart                                # Punto de entrada y captura de errores en zona segura

android/app/src/main/kotlin/com/example/media_downloader/
├── MainActivity.kt                          # Canales con Flutter, selector de carpetas y permisos
├── YtDlpEngine.kt                           # Inicialización, actualización, análisis y progreso de yt-dlp
├── YouTubeFastExtractor.kt                  # YouTube sin yt-dlp: API ios_producer
├── DirectDownloader.kt                      # Descarga HTTP por bloques con varias conexiones
├── DownloadService.kt                       # Servicio en primer plano que ejecuta la descarga
├── DownloadStateHolder.kt                   # Estado compartido de la descarga (sobrevive a la Activity)
├── MediaTools.kt                            # Unión de pistas y conversión de audio (MediaMuxer/MediaCodec)
├── Mp3Encoder.kt                            # Puente JNI con LAME
└── MediaExporter.kt                         # Exportación a MediaStore/SAF y apertura de carpetas

android/app/src/main/cpp/                    # CMake que descarga y compila LAME 3.100 + puente JNI
```

---
