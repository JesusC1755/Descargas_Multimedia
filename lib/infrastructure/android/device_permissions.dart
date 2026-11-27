import 'package:flutter/services.dart';

enum AppPermission { storage, notifications, battery }

enum PermissionState { granted, denied, notRequired }

/// Permisos de Android que usa la app (ver `AppPermissions.kt`).
class DevicePermissions {
  static const MethodChannel _channel = MethodChannel('com.example.media_downloader/permissions');

  static Future<Map<AppPermission, PermissionState>> status() async {
    final raw = await _channel.invokeMapMethod<String, String>('status') ?? const {};
    return {
      for (final p in AppPermission.values)
        p: PermissionState.values.firstWhere((s) => s.name == raw[p.name], orElse: () => PermissionState.denied),
    };
  }

  /// Pide el permiso y devuelve si quedó concedido. Con [openSettings], si Android ya no
  /// muestra el diálogo, abre la pantalla de ajustes del sistema que corresponde.
  static Future<bool> request(AppPermission permission, {bool openSettings = false}) async {
    return await _channel.invokeMethod<bool>('request', {
          'name': permission.name,
          'openSettings': openSettings,
        }) ??
        false;
  }
}
