import 'dart:io';

import 'package:flutter/services.dart';

/// Texto que otras apps comparten con Media Downloader (menú Compartir de Android),
/// normalmente "Título https://…".
class SharedText {
  static const MethodChannel _channel = MethodChannel('com.example.media_downloader/share');

  /// Llama a [onText] con el texto con el que se abrió la app y con los que lleguen después.
  static Future<void> listen(void Function(String text) onText) async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      final text = call.arguments;
      if (call.method == 'sharedText' && text is String) onText(text);
    });
    final initial = await _channel.invokeMethod<String>('takeSharedText');
    if (initial != null) onText(initial);
  }

  static void cancel() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(null);
  }
}
