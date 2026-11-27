import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/domain/models/stream_option.dart';
import 'package:media_downloader/infrastructure/desktop/desktop_process_engine.dart';

Map<String, dynamic> _video(String id, int width, int height, String vcodec) => {
      'format_id': id,
      'width': width,
      'height': height,
      'vcodec': vcodec,
      'acodec': 'none',
    };

/// Formatos típicos de YouTube: H.264 hasta 1080p, VP9/AV1 en 1440p y 4K,
/// un 72p residual, audio y storyboard.
final Map<String, dynamic> _youtubeJson = {
  'title': 'Video de prueba',
  'uploader': 'Canal',
  'duration': 232.4,
  'formats': [
    {'format_id': 'sb0', 'vcodec': 'none', 'acodec': 'none', 'ext': 'mhtml'},
    {'format_id': '140', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'ext': 'm4a'},
    _video('597', 128, 72, 'avc1.4d400b'),
    _video('160', 256, 144, 'avc1.4d400c'),
    _video('133', 426, 240, 'avc1.4d4015'),
    _video('134', 640, 360, 'avc1.4d401e'),
    _video('135', 854, 480, 'avc1.4d401f'),
    _video('136', 1280, 720, 'avc1.64001f'),
    _video('137', 1920, 1080, 'avc1.640028'),
    _video('271', 2560, 1440, 'vp9'),
    _video('313', 3840, 2160, 'vp9'),
    _video('401', 3840, 2160, 'av01.0.12M.08'),
  ],
};

List<int?> _heights(Map<String, dynamic> json, {bool h264Only = false, int? maxHeight}) =>
    DesktopProcessEngine.parseMediaInfo(json, 'https://example.com', h264Only: h264Only, maxHeight: maxHeight)
        .videoOptions
        .map((o) => o.height)
        .toList();

void main() {
  group('parseMediaInfo', () {
    test('escritorio ofrece todas las resoluciones y descarta 72p', () {
      expect(_heights(_youtubeJson), [2160, 1440, 1080, 720, 480, 360, 240, 144]);
    });

    test('Android (H.264 hasta 1080p) no ofrece 1440p ni 4K', () {
      expect(_heights(_youtubeJson, h264Only: true, maxHeight: 1080), [1080, 720, 480, 360, 240, 144]);
    });

    test('conserva 72p si es la única resolución', () {
      final json = {
        'title': 'Solo 72p',
        'formats': [_video('597', 128, 72, 'avc1.4d400b')],
      };
      expect(_heights(json), [72]);
    });

    test('videos verticales usan el lado menor (1080x1920 → 1080p)', () {
      final json = {
        'title': 'Reel',
        'formats': [_video('v1', 1080, 1920, 'avc1.640028')],
      };
      expect(_heights(json), [1080]);
    });

    test('formatos sin códec ni dimensiones (Facebook SD/HD) se infieren y se conservan con h264Only', () {
      final json = {
        'title': 'Facebook',
        'formats': [
          {'format_id': 'sd', 'format_note': 'sd'},
          {'format_id': 'hd', 'format_note': 'hd'},
        ],
      };
      expect(_heights(json, h264Only: true, maxHeight: 1080), [720, 480]);
    });

    test('sin formatos de video ofrece "Mejor Calidad Disponible"', () {
      final info = DesktopProcessEngine.parseMediaInfo({'title': 'x', 'formats': []}, 'https://example.com');
      expect(info.videoOptions.single.label, 'Mejor Calidad Disponible (MP4)');
      expect(info.durationSeconds, isNull);
    });

    test('lee título, autor y duración', () {
      final info = DesktopProcessEngine.parseMediaInfo(_youtubeJson, 'https://example.com');
      expect(info.title, 'Video de prueba');
      expect(info.uploader, 'Canal');
      expect(info.durationSeconds, 232);
      expect(info.audioOptions.map((o) => o.extension), ['m4a', 'mp3', 'opus', 'flac']);
    });
  });

  group('buildVideoFormatSelector', () {
    test('prioriza H.264 + AAC', () {
      final selector = DesktopProcessEngine.buildVideoFormatSelector(height: 1080, h264Only: false);
      expect(selector.split('/').first, 'bv*[height<=1940][width<=1940][vcodec^=avc1]+ba[acodec^=mp4a]');
    });

    test('escritorio admite cualquier códec como último recurso (se recodifica)', () {
      final parts = DesktopProcessEngine.buildVideoFormatSelector(height: 1080, h264Only: false).split('/');
      expect(parts, contains('bv*+ba'));
    });

    test('Android nunca elige VP9/AV1 sin filtrar', () {
      final parts = DesktopProcessEngine.buildVideoFormatSelector(height: 1080, h264Only: true).split('/');
      expect(parts, isNot(contains('bv*+ba')));
      expect(parts.where((p) => p.startsWith('bv*')).every((p) => p.contains('avc1') || p.contains('h264')), isTrue);
    });

    test('no repite alternativas', () {
      final parts = DesktopProcessEngine.buildVideoFormatSelector(height: null, h264Only: false).split('/');
      expect(parts.toSet().length, parts.length);
    });
  });

  group('peso de cada opción', () {
    const mb = 1024 * 1024;
    final json = {
      'title': 'Pesos',
      'duration': 200,
      'formats': [
        {'format_id': '140', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'filesize': 3 * mb, 'tbr': 128},
        {'format_id': '251', 'vcodec': 'none', 'acodec': 'opus', 'filesize': 2 * mb, 'tbr': 130},
        {..._video('137', 1920, 1080, 'avc1.640028'), 'filesize': 60 * mb},
        {..._video('248', 1920, 1080, 'vp9'), 'filesize': 40 * mb},
        {..._video('136', 1280, 720, 'avc1.4d401f'), 'tbr': 1000},
        _video('135', 854, 480, 'avc1.4d401e'),
      ],
    };
    final info = DesktopProcessEngine.parseMediaInfo(json, 'https://example.com');
    StreamOption videoAt(int h) => info.videoOptions.firstWhere((o) => o.height == h);
    StreamOption audio(String ext) => info.audioOptions.firstWhere((o) => o.extension == ext);

    test('video exacto: H.264 de esa resolución + audio AAC', () {
      expect(videoAt(1080).filesize, 63 * mb);
      expect(videoAt(1080).filesizeIsApprox, isFalse);
    });

    test('sin tamaño se estima con el bitrate y la duración', () {
      expect(videoAt(720).filesize, 1000 * 1000 ~/ 8 * 200 + 3 * mb);
      expect(videoAt(720).filesizeIsApprox, isTrue);
    });

    test('sin tamaño ni bitrate no se muestra peso', () {
      expect(videoAt(480).filesize, isNull);
    });

    test('progresivo (video con audio) no suma otra pista', () {
      final progressive = DesktopProcessEngine.parseMediaInfo({
        'title': 'Facebook',
        'formats': [
          {'format_id': 'hd', 'format_note': 'hd', 'vcodec': 'avc1', 'acodec': 'mp4a', 'filesize': 9 * mb},
          {'format_id': 'a', 'vcodec': 'none', 'acodec': 'mp4a', 'filesize': mb},
        ],
      }, 'https://example.com');
      expect(progressive.videoOptions.single.filesize, 9 * mb);
    });

    test('audio: M4A y Opus exactos; MP3 y FLAC estimados por duración', () {
      expect(audio('m4a').filesize, 3 * mb);
      expect(audio('opus').filesize, 2 * mb);
      expect(audio('mp3').filesize, 245 * 1000 ~/ 8 * 200);
      expect(audio('mp3').filesizeIsApprox, isTrue);
      expect(audio('flac').filesizeIsApprox, isTrue);
    });
  });
}
