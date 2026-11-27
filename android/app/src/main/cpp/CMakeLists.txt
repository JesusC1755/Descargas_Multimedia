cmake_minimum_required(VERSION 3.22.1)
project(mp3lame_jni C)

# LAME 3.100 (última versión, de 2017) se descarga en la primera compilación y queda en la caché
# de compilación. El sha256 garantiza que siempre es el mismo archivo; Debian es la réplica.
include(FetchContent)
FetchContent_Declare(lame
        URL https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
            http://deb.debian.org/debian/pool/main/l/lame/lame_3.100.orig.tar.gz
        URL_HASH SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e)
FetchContent_GetProperties(lame)
if (NOT lame_POPULATED)
    # Solo se usan las fuentes: el CMake/autotools de LAME no se ejecuta.
    FetchContent_Populate(lame)
endif ()

# Solo el codificador (sin mpglib ni rutinas SSE): convierte PCM a MP3.
file(GLOB LAME_SOURCES ${lame_SOURCE_DIR}/libmp3lame/*.c)
list(FILTER LAME_SOURCES EXCLUDE REGEX ".*/mpglib_interface\\.c$")

add_library(mp3lame_jni SHARED ${LAME_SOURCES} mp3_encoder_jni.c)

target_include_directories(mp3lame_jni PRIVATE
        ${lame_SOURCE_DIR}/include
        ${lame_SOURCE_DIR}/libmp3lame)

# Sustituyen a config.h, que en LAME genera ./configure.
target_compile_definitions(mp3lame_jni PRIVATE
        STDC_HEADERS HAVE_STDINT_H HAVE_INTTYPES_H HAVE_LIMITS_H HAVE_STRING_H HAVE_STDLIB_H
        ieee754_float32_t=float)

target_compile_options(mp3lame_jni PRIVATE -O3 -w -ffunction-sections -fdata-sections)
target_link_options(mp3lame_jni PRIVATE -Wl,--gc-sections -s)
target_link_libraries(mp3lame_jni m)
