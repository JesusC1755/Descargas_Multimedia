import 'dart:io';

import '../domain/ports/media_engine_port.dart';
import 'android/android_native_engine.dart';
import 'desktop/desktop_process_engine.dart';

class MediaEngineFactory {
  static IMediaEngine create() {
    if (Platform.isAndroid) {
      return AndroidNativeEngine();
    }
    return DesktopProcessEngine();
  }
}

