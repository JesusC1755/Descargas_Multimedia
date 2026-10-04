import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/core/utils/media_url_validator.dart';

void main() {
  group('MediaUrlValidator Tests', () {
    test('Rechaza entradas vacías o nulas', () {
      expect(MediaUrlValidator.validate(null).isValid, isFalse);
      expect(MediaUrlValidator.validate('').isValid, isFalse);
      expect(MediaUrlValidator.validate('   ').isValid, isFalse);
    });

    test('Rechaza cadenas que no son URLs válidas', () {
      final res = MediaUrlValidator.validate('hola mundo como estas');
      expect(res.isValid, isFalse);
      expect(res.errorMessage, contains('no es una dirección web válida'));
    });

    test('Rechaza dominios web que no son plataformas de video', () {
      final resGoogle = MediaUrlValidator.validate('https://www.google.com/search?q=flutter');
      expect(resGoogle.isValid, isFalse);
      expect(resGoogle.errorMessage, contains('no corresponde a un video'));

      final resWiki = MediaUrlValidator.validate('https://es.wikipedia.org/wiki/Dart');
      expect(resWiki.isValid, isFalse);

      final resGithub = MediaUrlValidator.validate('https://github.com/flutter/flutter');
      expect(resGithub.isValid, isFalse);
    });

    group('YouTube', () {
      test('Acepta enlaces estándar watch?v=...', () {
        final res = MediaUrlValidator.validate('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
        expect(res.isValid, isTrue);
        expect(res.platform, equals(MediaPlatform.youtube));
        expect(res.cleanUrl, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
      });

      test('Limpia parámetros de tracking en YouTube', () {
        final res = MediaUrlValidator.validate('https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=123456&feature=share');
        expect(res.isValid, isTrue);
        expect(res.cleanUrl, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
      });

      test('Acepta y limpia youtu.be', () {
        final res = MediaUrlValidator.validate('https://youtu.be/dQw4w9WgXcQ?si=abcdef');
        expect(res.isValid, isTrue);
        expect(res.cleanUrl, equals('https://youtu.be/dQw4w9WgXcQ'));
      });

      test('Acepta YouTube Shorts', () {
        final res = MediaUrlValidator.validate('https://www.youtube.com/shorts/3i_e1G-0h40');
        expect(res.isValid, isTrue);
        expect(res.cleanUrl, equals('https://www.youtube.com/shorts/3i_e1G-0h40'));
      });

      test('Rechaza home de YouTube o perfiles sin video', () {
        final home = MediaUrlValidator.validate('https://www.youtube.com/');
        expect(home.isValid, isFalse);
        expect(home.errorMessage, contains('página principal de YouTube'));

        final canal = MediaUrlValidator.validate('https://www.youtube.com/@FlutterDev');
        expect(canal.isValid, isFalse);
        expect(canal.errorMessage, contains('canal o perfil'));
      });
    });

    group('TikTok', () {
      test('Acepta video estándar de TikTok', () {
        final res = MediaUrlValidator.validate('https://www.tiktok.com/@mrbeast/video/7123456789012345678');
        expect(res.isValid, isTrue);
        expect(res.platform, equals(MediaPlatform.tiktok));
      });

      test('Acepta enlace corto vt.tiktok.com', () {
        final res = MediaUrlValidator.validate('https://vm.tiktok.com/ZM8123456/');
        expect(res.isValid, isTrue);
      });

      test('Rechaza perfil de TikTok', () {
        final res = MediaUrlValidator.validate('https://www.tiktok.com/@mrbeast');
        expect(res.isValid, isFalse);
      });
    });

    group('Instagram', () {
      test('Acepta Reels y publicaciones de video', () {
        final reel = MediaUrlValidator.validate('https://www.instagram.com/reel/C3abcde1234/');
        expect(reel.isValid, isTrue);
        expect(reel.platform, equals(MediaPlatform.instagram));

        final post = MediaUrlValidator.validate('https://www.instagram.com/p/C3abcde1234/?igsh=123');
        expect(post.isValid, isTrue);
        expect(post.cleanUrl, equals('https://www.instagram.com/p/C3abcde1234/'));
      });

      test('Rechaza perfiles o home de Instagram', () {
        final res = MediaUrlValidator.validate('https://www.instagram.com/flutterdev');
        expect(res.isValid, isFalse);
      });
    });

    group('Twitter / X', () {
      test('Acepta tweets con status', () {
        final res = MediaUrlValidator.validate('https://x.com/flutterdev/status/1234567890?s=20');
        expect(res.isValid, isTrue);
        expect(res.cleanUrl, equals('https://x.com/flutterdev/status/1234567890'));
      });

      test('Rechaza perfil de X', () {
        final res = MediaUrlValidator.validate('https://x.com/flutterdev');
        expect(res.isValid, isFalse);
      });
    });

    group('Otras plataformas y archivos directos', () {
      test('Acepta Facebook Watch y Reels', () {
        final res = MediaUrlValidator.validate('https://fb.watch/abcd1234ef/');
        expect(res.isValid, isTrue);
      });

      test('Acepta Twitch VODs y clips', () {
        final clip = MediaUrlValidator.validate('https://clips.twitch.tv/GloriousTameOcelot');
        expect(clip.isValid, isTrue);
      });

      test('Acepta enlaces directos a archivos .mp4 y .webm', () {
        final mp4 = MediaUrlValidator.validate('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4');
        expect(mp4.isValid, isTrue);
        expect(mp4.platform, equals(MediaPlatform.directVideo));
      });
    });
  });
}
