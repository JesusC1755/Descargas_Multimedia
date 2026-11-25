# Reglas de R8 para la compilación release (Flutter carga este archivo automáticamente).

# youtubedl-android no publica reglas propias y usa Jackson (reflexión) para leer
# las respuestas de yt-dlp y del actualizador: conservar sus clases.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-dontwarn com.fasterxml.jackson.**

# commons-compress descomprime Python/FFmpeg en el primer arranque y registra sus
# clases ZIP por reflexión ("class … is not a concrete class" si R8 las modifica).
-keep class org.apache.commons.compress.** { *; }

# Dependencias opcionales de commons-compress que no se usan.
-dontwarn org.apache.commons.compress.**
-dontwarn org.tukaani.xz.**
-dontwarn org.brotli.dec.**
-dontwarn com.github.luben.zstd.**
-dontwarn org.objectweb.asm.**
