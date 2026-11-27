import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/infrastructure/desktop/desktop_process_engine.dart';
import 'package:media_downloader/infrastructure/youtube/youtube_direct.dart';

Map<String, dynamic> _fmt(int itag, String mime, {int? w, int? h, int bitrate = 1000, Map? track}) => {
      'itag': itag,
      'url': 'https://rr.googlevideo.com/videoplayback?itag=$itag',
      'mimeType': mime,
      'bitrate': bitrate,
      'contentLength': '${itag * 1000}',
      if (w != null) 'width': w,
      if (h != null) 'height': h,
      if (h != null) 'qualityLabel': '${h}p',
      if (track != null) 'audioTrack': track,
    };

Map<String, dynamic> _response({String status = 'OK', bool live = false}) => {
      'playabilityStatus': {'status': status, 'reason': 'motivo'},
      'videoDetails': {
        'videoId': 'dQw4w9WgXcQ',
        'title': 'Título',
        'author': 'Canal',
        'lengthSeconds': '213',
        'isLive': live,
        'thumbnail': {
          'thumbnails': [
            {'url': 'https://i.ytimg.com/small.jpg', 'width': 120, 'height': 90},
            {'url': 'https://i.ytimg.com/big.jpg', 'width': 1920, 'height': 1080},
          ],
        },
      },
      'streamingData': {
        'adaptiveFormats': [
          _fmt(137, 'video/mp4; codecs="avc1.640028"', w: 1920, h: 1080, bitrate: 4000),
          _fmt(136, 'video/mp4; codecs="avc1.4D401F"', w: 1280, h: 720, bitrate: 2000),
          _fmt(134, 'video/mp4; codecs="avc1.4D401E"', w: 640, h: 360, bitrate: 600),
          _fmt(139, 'audio/mp4; codecs="mp4a.40.5"', bitrate: 48000),
          _fmt(140, 'audio/mp4; codecs="mp4a.40.2"', bitrate: 129000),
          {'itag': 251, 'mimeType': 'audio/webm; codecs="opus"', 'signatureCipher': 's=...'},
        ],
      },
    };

void main() {
  group('videoIdOf', () {
    test('reconoce los formatos de enlace de YouTube', () {
      for (final url in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RD',
        'https://youtu.be/dQw4w9WgXcQ?t=10',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/live/dQw4w9WgXcQ',
      ]) {
        expect(YouTubeDirectClient.videoIdOf(url), 'dQw4w9WgXcQ', reason: url);
      }
    });

    test('ignora otros sitios', () {
      expect(YouTubeDirectClient.videoIdOf('https://www.tiktok.com/@a/video/123'), isNull);
      expect(YouTubeDirectClient.videoIdOf('https://www.youtube.com/@canal'), isNull);
    });
  });

  group('parsePlayerResponse', () {
    test('genera el formato de yt-dlp y omite los formatos cifrados', () {
      final info = YouTubeDirectClient.parsePlayerResponse(_response(), 'dQw4w9WgXcQ');
      expect(info['_engine'], YouTubeDirectClient.engine);
      expect(info['title'], 'Título');
      expect(info['duration'], 213);
      expect(info['thumbnail'], 'https://i.ytimg.com/big.jpg');
      final formats = (info['formats'] as List).cast<Map<String, dynamic>>();
      expect(formats.map((f) => f['format_id']), ['137', '136', '134', '139', '140']);
      final audio = formats.firstWhere((f) => f['format_id'] == '140');
      expect(audio['vcodec'], 'none');
      expect(audio['acodec'], 'mp4a.40.2');
      expect(audio['ext'], 'm4a');
      expect(audio['filesize'], 140000);
    });

    test('lo entiende parseMediaInfo', () {
      final info = YouTubeDirectClient.parsePlayerResponse(_response(), 'dQw4w9WgXcQ');
      final media = DesktopProcessEngine.parseMediaInfo(info, 'url', h264Only: true, maxHeight: 1080);
      expect(media.videoOptions.map((o) => o.height), [1080, 720, 360]);
    });

    test('rechaza vídeos no reproducibles y directos', () {
      expect(() => YouTubeDirectClient.parsePlayerResponse(_response(status: 'LOGIN_REQUIRED'), 'dQw4w9WgXcQ'),
          throwsStateError);
      expect(() => YouTubeDirectClient.parsePlayerResponse(_response(live: true), 'dQw4w9WgXcQ'), throwsStateError);
    });
  });

  group('pickFormats', () {
    final info = YouTubeDirectClient.parsePlayerResponse(_response(), 'dQw4w9WgXcQ');

    test('elige la mayor resolución que no supera la pedida y el mejor AAC', () {
      final picked = YouTubeDirectClient.pickFormats(info, audioOnly: false, height: 720);
      expect(picked.video?['format_id'], '136');
      expect(picked.audio['format_id'], '140');
    });

    test('solo audio no elige vídeo', () {
      final picked = YouTubeDirectClient.pickFormats(info, audioOnly: true);
      expect(picked.video, isNull);
    });
  });
}
