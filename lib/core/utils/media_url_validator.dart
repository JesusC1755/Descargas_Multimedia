import 'package:flutter/material.dart';

/// Plataformas multimedia compatibles reconocidas por el analizador.
enum MediaPlatform {
  youtube('YouTube', Icons.smart_display_rounded),
  tiktok('TikTok', Icons.music_video_rounded),
  instagram('Instagram', Icons.camera_alt_rounded),
  twitter('X / Twitter', Icons.tag_rounded),
  facebook('Facebook', Icons.facebook_rounded),
  twitch('Twitch', Icons.videogame_asset_rounded),
  reddit('Reddit', Icons.forum_rounded),
  vimeo('Vimeo', Icons.movie_filter_rounded),
  dailymotion('Dailymotion', Icons.play_arrow_rounded),
  soundCloud('SoundCloud', Icons.graphic_eq_rounded),
  threads('Threads', Icons.alternate_email_rounded),
  pinterest('Pinterest', Icons.push_pin_rounded),
  directVideo('Video Directo', Icons.video_file_rounded),
  unknown('Desconocido', Icons.link_off_rounded);

  final String displayName;
  final IconData icon;

  const MediaPlatform(this.displayName, this.icon);
}

/// Resultado de la validación y sanitización de una URL multimedia.
class MediaUrlValidationResult {
  final bool isValid;
  final String? cleanUrl;
  final MediaPlatform platform;
  final String? platformDisplayName;
  final String? errorMessage;
  final String? warningMessage;

  const MediaUrlValidationResult({
    required this.isValid,
    this.cleanUrl,
    this.platform = MediaPlatform.unknown,
    this.platformDisplayName,
    this.errorMessage,
    this.warningMessage,
  });

  bool get isVideo => isValid;
}

/// Validador centralizado de URLs para descargas multimedia.
/// Aplica reglas de negocio para rechazar enlaces no compatibles, páginas de inicio
/// o textos arbitrarios antes de invocar subprocesos externos (yt-dlp).
class MediaUrlValidator {
  static const Set<String> _videoExtensions = {
    '.mp4',
    '.webm',
    '.mkv',
    '.mov',
    '.avi',
    '.m3u8',
    '.mpd',
    '.ts',
    '.flv',
  };

  static const Set<String> _trackingQueryParams = {
    'si',
    'feature',
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_term',
    'utm_content',
    'fbclid',
    'igsh',
    'igshid',
    's',
    'ref',
    'ref_src',
    'share_id',
    'source',
  };

  /// Valida una cadena de texto para determinar si es una URL de video válida.
  static MediaUrlValidationResult validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage: 'Por favor, ingresa o pega el enlace de un video.',
      );
    }

    final trimmed = input.trim();

    // Comprobación de protocolo básico
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage:
            'El texto ingresado no es una dirección web válida (debe comenzar con https:// o http://).',
      );
    }

    final host = uri.host.toLowerCase().replaceAll(RegExp(r'^www\.'), '');
    final path = uri.path;
    final pathLower = path.toLowerCase();

    // 1. Detección de enlaces directos a archivos de video
    for (final ext in _videoExtensions) {
      if (pathLower.endsWith(ext)) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: trimmed,
          platform: MediaPlatform.directVideo,
          platformDisplayName: MediaPlatform.directVideo.displayName,
        );
      }
    }

    // 2. YouTube
    if (host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be') {
      return _validateYouTube(uri, host, trimmed);
    }

    // 3. TikTok
    if (host == 'tiktok.com' || host.endsWith('.tiktok.com')) {
      return _validateTikTok(uri, host, trimmed);
    }

    // 4. Instagram
    if (host == 'instagram.com' || host == 'instagr.am') {
      return _validateInstagram(uri, trimmed);
    }

    // 5. Twitter / X
    if (host == 'twitter.com' ||
        host == 'x.com' ||
        host.endsWith('.twitter.com')) {
      return _validateTwitter(uri, trimmed);
    }

    // 6. Facebook
    if (host == 'facebook.com' ||
        host.endsWith('.facebook.com') ||
        host == 'fb.watch' ||
        host == 'fb.com') {
      return _validateFacebook(uri, host, trimmed);
    }

    // 7. Twitch
    if (host == 'twitch.tv' || host.endsWith('.twitch.tv')) {
      return _validateTwitch(uri, host, trimmed);
    }

    // 8. Reddit
    if (host == 'reddit.com' ||
        host.endsWith('.reddit.com') ||
        host == 'v.redd.it') {
      return _validateReddit(uri, host, trimmed);
    }

    // 9. Vimeo
    if (host == 'vimeo.com' || host.endsWith('.vimeo.com')) {
      return _validateVimeo(uri, trimmed);
    }

    // 10. Dailymotion
    if (host == 'dailymotion.com' ||
        host.endsWith('.dailymotion.com') ||
        host == 'dai.ly') {
      return _validateDailymotion(uri, host, trimmed);
    }

    // 11. SoundCloud
    if (host == 'soundcloud.com' || host.endsWith('.soundcloud.com')) {
      return _validateSoundCloud(uri, trimmed);
    }

    // 12. Threads
    if (host == 'threads.net' || host.endsWith('.threads.net')) {
      return _validateThreads(uri, trimmed);
    }

    // 13. Pinterest
    if (host == 'pinterest.com' ||
        host.endsWith('.pinterest.com') ||
        host == 'pin.it') {
      return _validatePinterest(uri, host, trimmed);
    }

    // Enlace web general no reconocido como plataforma de video compatible
    return MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'Este enlace ($host) no corresponde a un video ni a una plataforma compatible.\n'
          'Soportadas: YouTube, TikTok, Instagram, X (Twitter), Facebook, Twitch, Reddit, Vimeo o enlaces directos (.mp4).',
    );
  }

  // --- Validadores específicos por plataforma ---

  static MediaUrlValidationResult _validateYouTube(
    Uri uri,
    String host,
    String original,
  ) {
    // Caso youtu.be/<id>
    if (host == 'youtu.be') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isEmpty) {
        return const MediaUrlValidationResult(
          isValid: false,
          errorMessage: 'El enlace corto youtu.be no contiene un ID de video válido.',
        );
      }
      final videoId = segments.first;
      final timeParam = uri.queryParameters['t'];
      final clean = timeParam != null
          ? 'https://youtu.be/$videoId?t=$timeParam'
          : 'https://youtu.be/$videoId';

      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: clean,
        platform: MediaPlatform.youtube,
        platformDisplayName: MediaPlatform.youtube.displayName,
      );
    }

    final path = uri.path;

    // Caso /watch?v=...
    if (path == '/watch' || path.startsWith('/watch/')) {
      final videoId = uri.queryParameters['v'];
      if (videoId == null || videoId.trim().isEmpty) {
        return const MediaUrlValidationResult(
          isValid: false,
          errorMessage:
              'El enlace de YouTube no contiene el parámetro del video (?v=...).',
        );
      }
      final timeParam = uri.queryParameters['t'];
      final clean = timeParam != null
          ? 'https://www.youtube.com/watch?v=$videoId&t=$timeParam'
          : 'https://www.youtube.com/watch?v=$videoId';

      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: clean,
        platform: MediaPlatform.youtube,
        platformDisplayName: MediaPlatform.youtube.displayName,
      );
    }

    // Caso /shorts/<id>
    if (path.startsWith('/shorts/')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2 && segments[1].isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://www.youtube.com/shorts/${segments[1]}',
          platform: MediaPlatform.youtube,
          platformDisplayName: 'YouTube Shorts',
        );
      }
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage: 'El enlace de YouTube Shorts no contiene un ID de video válido.',
      );
    }

    // Caso /live/<id> o /embed/<id> o /v/<id>
    if (path.startsWith('/live/') ||
        path.startsWith('/embed/') ||
        path.startsWith('/v/')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2 && segments[1].isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://www.youtube.com/watch?v=${segments[1]}',
          platform: MediaPlatform.youtube,
          platformDisplayName: MediaPlatform.youtube.displayName,
        );
      }
    }

    // Página de inicio o canales
    if (path.isEmpty || path == '/') {
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage:
            'El enlace apunta a la página principal de YouTube. Por favor ingresa el enlace de un video o Short específico.',
      );
    }

    if (path.startsWith('/channel/') ||
        path.startsWith('/c/') ||
        path.startsWith('/@') ||
        path.startsWith('/user/')) {
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage:
            'El enlace apunta a un canal o perfil de YouTube, no a un video descargable.',
      );
    }

    if (path.startsWith('/playlist')) {
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage:
            'El enlace apunta a una lista de reproducción completa. Por favor ingresa el enlace de un video individual.',
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'No se reconoció un video válido en este enlace de YouTube. Debe ser /watch?v=... o /shorts/...',
    );
  }

  static MediaUrlValidationResult _validateTikTok(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'vm.tiktok.com' || host == 'vt.tiktok.com') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://$host/${segments.first}',
          platform: MediaPlatform.tiktok,
          platformDisplayName: MediaPlatform.tiktok.displayName,
        );
      }
      return const MediaUrlValidationResult(
        isValid: false,
        errorMessage: 'Enlace corto de TikTok inválido.',
      );
    }

    final path = uri.path;
    if (path.contains('/video/') || path.startsWith('/v/') || path.startsWith('/t/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.tiktok,
        platformDisplayName: MediaPlatform.tiktok.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace apunta a la página principal o a un perfil de TikTok. Ingresa el enlace de un video específico.',
    );
  }

  static MediaUrlValidationResult _validateInstagram(Uri uri, String original) {
    final path = uri.path;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (path.startsWith('/reel/') ||
        path.startsWith('/reels/') ||
        path.startsWith('/p/') ||
        path.startsWith('/tv/')) {
      if (segments.length >= 2 && segments[1].isNotEmpty) {
        final clean = 'https://www.instagram.com/${segments[0]}/${segments[1]}/';
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: clean,
          platform: MediaPlatform.instagram,
          platformDisplayName: path.startsWith('/reel')
              ? 'Instagram Reel'
              : MediaPlatform.instagram.displayName,
        );
      }
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Instagram debe pertenecer a un Reel (/reel/) o publicación de video (/p/).',
    );
  }

  static MediaUrlValidationResult _validateTwitter(Uri uri, String original) {
    final path = uri.path;
    if (path.contains('/status/')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final statusIndex = segments.indexOf('status');
      if (statusIndex != -1 && statusIndex + 1 < segments.length) {
        final user = statusIndex > 0 ? segments[statusIndex - 1] : 'i';
        final statusId = segments[statusIndex + 1];
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://x.com/$user/status/$statusId',
          platform: MediaPlatform.twitter,
          platformDisplayName: MediaPlatform.twitter.displayName,
        );
      }
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de X/Twitter debe ser de una publicación o tweet específico (/status/).',
    );
  }

  static MediaUrlValidationResult _validateFacebook(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'fb.watch' || host == 'fb.com') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: _stripTrackingParams(uri),
          platform: MediaPlatform.facebook,
          platformDisplayName: MediaPlatform.facebook.displayName,
        );
      }
    }

    final path = uri.path;
    final hasVideoQuery = uri.queryParameters.containsKey('v');
    final isVideoPath = path.contains('/watch') ||
        path.contains('/reel/') ||
        path.contains('/videos/') ||
        path.contains('/share/r/') ||
        path.contains('/share/v/');

    if (hasVideoQuery || isVideoPath) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.facebook,
        platformDisplayName: path.contains('/reel/')
            ? 'Facebook Reel'
            : MediaPlatform.facebook.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Facebook debe apuntar a un video, Watch o Reel específico.',
    );
  }

  static MediaUrlValidationResult _validateTwitch(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'clips.twitch.tv') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://clips.twitch.tv/${segments.first}',
          platform: MediaPlatform.twitch,
          platformDisplayName: 'Twitch Clip',
        );
      }
    }

    final path = uri.path;
    if (path.startsWith('/videos/') || path.contains('/clip/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.twitch,
        platformDisplayName: MediaPlatform.twitch.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Twitch debe ser de un video guardado (VOD) o clip específico, no del canal en vivo.',
    );
  }

  static MediaUrlValidationResult _validateReddit(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'v.redd.it') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://v.redd.it/${segments.first}',
          platform: MediaPlatform.reddit,
          platformDisplayName: MediaPlatform.reddit.displayName,
        );
      }
    }

    final path = uri.path;
    if (path.contains('/comments/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.reddit,
        platformDisplayName: MediaPlatform.reddit.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Reddit debe apuntar a una publicación específica con video (/comments/).',
    );
  }

  static MediaUrlValidationResult _validateVimeo(Uri uri, String original) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isNotEmpty &&
        !segments.contains('upgrade') &&
        !segments.contains('explore')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.vimeo,
        platformDisplayName: MediaPlatform.vimeo.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage: 'El enlace de Vimeo debe contener el identificador de un video.',
    );
  }

  static MediaUrlValidationResult _validateDailymotion(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'dai.ly') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://dai.ly/${segments.first}',
          platform: MediaPlatform.dailymotion,
          platformDisplayName: MediaPlatform.dailymotion.displayName,
        );
      }
    }

    final path = uri.path;
    if (path.contains('/video/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.dailymotion,
        platformDisplayName: MediaPlatform.dailymotion.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Dailymotion debe apuntar a un video específico (/video/).',
    );
  }

  static MediaUrlValidationResult _validateSoundCloud(Uri uri, String original) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 &&
        !segments.contains('discover') &&
        !segments.contains('stream')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.soundCloud,
        platformDisplayName: MediaPlatform.soundCloud.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de SoundCloud debe ser de una pista de audio específica (/artista/cancion).',
    );
  }

  static MediaUrlValidationResult _validateThreads(Uri uri, String original) {
    final path = uri.path;
    if (path.contains('/post/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.threads,
        platformDisplayName: MediaPlatform.threads.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage:
          'El enlace de Threads debe ser de una publicación específica (/post/).',
    );
  }

  static MediaUrlValidationResult _validatePinterest(
    Uri uri,
    String host,
    String original,
  ) {
    if (host == 'pin.it') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        return MediaUrlValidationResult(
          isValid: true,
          cleanUrl: 'https://pin.it/${segments.first}',
          platform: MediaPlatform.pinterest,
          platformDisplayName: MediaPlatform.pinterest.displayName,
        );
      }
    }

    final path = uri.path;
    if (path.contains('/pin/')) {
      return MediaUrlValidationResult(
        isValid: true,
        cleanUrl: _stripTrackingParams(uri),
        platform: MediaPlatform.pinterest,
        platformDisplayName: MediaPlatform.pinterest.displayName,
      );
    }

    return const MediaUrlValidationResult(
      isValid: false,
      errorMessage: 'El enlace de Pinterest debe ser de un Pin específico (/pin/).',
    );
  }

  /// Limpia parámetros de rastreo y analíticas de la consulta URL.
  static String _stripTrackingParams(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri.toString();

    final filtered = Map<String, String>.from(uri.queryParameters)
      ..removeWhere((key, _) => _trackingQueryParams.contains(key.toLowerCase()));

    final cleanUri = uri.replace(queryParameters: filtered.isEmpty ? null : filtered);
    return cleanUri.toString();
  }
}
