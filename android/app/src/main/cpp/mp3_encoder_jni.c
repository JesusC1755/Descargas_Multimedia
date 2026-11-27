// Puente JNI mínimo hacia el codificador MP3 de LAME (ver Mp3Encoder.kt).
#include <jni.h>
#include <stdint.h>
#include "lame.h"

#define FN(name) Java_com_example_media_1downloader_Mp3Encoder_##name

JNIEXPORT jlong JNICALL FN(nativeInit)(JNIEnv *env, jclass clazz, jint sample_rate, jint channels, jint vbr_quality) {
    lame_global_flags *gf = lame_init();
    if (gf == NULL) return 0;
    lame_set_in_samplerate(gf, sample_rate);
    lame_set_num_channels(gf, channels);
    if (channels == 1) lame_set_mode(gf, MONO);
    lame_set_VBR(gf, vbr_default);
    lame_set_VBR_quality(gf, (float) vbr_quality);
    lame_set_write_id3tag_automatic(gf, 0);
    if (lame_init_params(gf) < 0) {
        lame_close(gf);
        return 0;
    }
    return (jlong) (intptr_t) gf;
}

/** Codifica [samples] muestras por canal de PCM 16 bits intercalado. Devuelve los bytes escritos en [out]. */
JNIEXPORT jint JNICALL FN(nativeEncode)(JNIEnv *env, jclass clazz, jlong handle, jshortArray pcm, jint samples, jbyteArray out) {
    lame_global_flags *gf = (lame_global_flags *) (intptr_t) handle;
    jshort *in = (*env)->GetShortArrayElements(env, pcm, NULL);
    jbyte *dst = (*env)->GetByteArrayElements(env, out, NULL);
    jsize dst_size = (*env)->GetArrayLength(env, out);
    int written;
    if (lame_get_num_channels(gf) == 1) {
        written = lame_encode_buffer(gf, in, in, samples, (unsigned char *) dst, dst_size);
    } else {
        written = lame_encode_buffer_interleaved(gf, in, samples, (unsigned char *) dst, dst_size);
    }
    (*env)->ReleaseShortArrayElements(env, pcm, in, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, out, dst, 0);
    return written;
}

JNIEXPORT jint JNICALL FN(nativeFlush)(JNIEnv *env, jclass clazz, jlong handle, jbyteArray out) {
    lame_global_flags *gf = (lame_global_flags *) (intptr_t) handle;
    jbyte *dst = (*env)->GetByteArrayElements(env, out, NULL);
    int written = lame_encode_flush(gf, (unsigned char *) dst, (*env)->GetArrayLength(env, out));
    (*env)->ReleaseByteArrayElements(env, out, dst, 0);
    return written;
}

/** Trama Xing/LAME con la duración real (VBR): va al inicio del archivo, en lugar de la primera trama. */
JNIEXPORT jint JNICALL FN(nativeLameTag)(JNIEnv *env, jclass clazz, jlong handle, jbyteArray out) {
    lame_global_flags *gf = (lame_global_flags *) (intptr_t) handle;
    jbyte *dst = (*env)->GetByteArrayElements(env, out, NULL);
    size_t size = lame_get_lametag_frame(gf, (unsigned char *) dst, (size_t) (*env)->GetArrayLength(env, out));
    (*env)->ReleaseByteArrayElements(env, out, dst, 0);
    return (jint) size;
}

JNIEXPORT void JNICALL FN(nativeClose)(JNIEnv *env, jclass clazz, jlong handle) {
    lame_close((lame_global_flags *) (intptr_t) handle);
}
