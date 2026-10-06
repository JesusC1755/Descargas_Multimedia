import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/domain/models/stream_option.dart';
import 'package:media_downloader/infrastructure/desktop/desktop_process_engine.dart';

void main() {
  group('DesktopProcessEngine Filename & Quality Tag Tests', () {
    test('getQualityTag genera etiquetas limpias para video y audio', () {
      const opt1080 = StreamOption(
        formatId: '137+140',
        label: 'Full HD (1080p)',
        extension: 'mp4',
        height: 1080,
      );
      expect(DesktopProcessEngine.getQualityTag(opt1080), equals('1080p'));

      const opt720 = StreamOption(
        formatId: '22',
        label: 'HD (720p)',
        extension: 'mp4',
        height: 720,
      );
      expect(DesktopProcessEngine.getQualityTag(opt720), equals('720p'));

      const opt4k = StreamOption(
        formatId: '313+140',
        label: '4K (2160p)',
        extension: 'mp4',
        height: 2160,
      );
      expect(DesktopProcessEngine.getQualityTag(opt4k), equals('2160p'));

      const optBest = StreamOption(
        formatId: 'best',
        label: 'Mejor Calidad Disponible (MP4)',
        extension: 'mp4',
      );
      expect(DesktopProcessEngine.getQualityTag(optBest), equals('Mejor Calidad'));

      const optMp3 = StreamOption(
        formatId: 'bestaudio',
        label: 'MP3',
        extension: 'mp3',
        isAudioOnly: true,
      );
      expect(DesktopProcessEngine.getQualityTag(optMp3), equals('MP3'));

      const optM4a = StreamOption(
        formatId: 'bestaudio',
        label: 'M4A',
        extension: 'm4a',
        isAudioOnly: true,
      );
      expect(DesktopProcessEngine.getQualityTag(optM4a), equals('M4A'));
    });

    test('sanitizeFilename limpia caracteres reservados y emojis', () {
      final sanitized = DesktopProcessEngine.sanitizeFilename('Video: ¡Prueba! / \\ * ? < > | 🔥 100% . ');
      expect(sanitized, isNot(contains(':')));
      expect(sanitized, isNot(contains('/')));
      expect(sanitized, isNot(contains('\\')));
      expect(sanitized, isNot(contains('🔥')));
      expect(sanitized.endsWith('.'), isFalse);
      expect(sanitized.endsWith(' '), isFalse);
    });

    test('resolveOutputBaseName diferencia calidades y evita colisiones duplicadas', () {
      final tempDir = Directory.systemTemp.createTempSync('media_dl_test_');

      try {
        const opt1080 = StreamOption(
          formatId: '137',
          label: '1080p',
          extension: 'mp4',
          height: 1080,
        );
        const opt720 = StreamOption(
          formatId: '22',
          label: '720p',
          extension: 'mp4',
          height: 720,
        );
        const optMp3 = StreamOption(
          formatId: 'bestaudio',
          label: 'MP3',
          extension: 'mp3',
          isAudioOnly: true,
        );

        // 1. Primera descarga a 1080p
        final name1 = DesktopProcessEngine.resolveOutputBaseName(
          customTitle: 'Cancion Genial',
          option: opt1080,
          downloadDir: tempDir.path,
        );
        expect(name1, equals('Cancion Genial [1080p]'));

        // Simulamos que el archivo de 1080p fue creado en disco
        File('${tempDir.path}/$name1.mp4').writeAsStringSync('dummy content 1080p');

        // 2. Descarga del mismo enlace a 720p: debe ser un archivo diferente
        final name720 = DesktopProcessEngine.resolveOutputBaseName(
          customTitle: 'Cancion Genial',
          option: opt720,
          downloadDir: tempDir.path,
        );
        expect(name720, equals('Cancion Genial [720p]'));

        // Simulamos que el archivo de 720p fue creado en disco
        File('${tempDir.path}/$name720.mp4').writeAsStringSync('dummy content 720p');

        // 3. Descarga del mismo enlace en MP3: debe ser otro archivo diferente
        final nameMp3 = DesktopProcessEngine.resolveOutputBaseName(
          customTitle: 'Cancion Genial',
          option: optMp3,
          downloadDir: tempDir.path,
        );
        expect(nameMp3, equals('Cancion Genial [MP3]'));

        // 4. Si se vuelve a descargar en 1080p (ya existiendo 'Cancion Genial [1080p].mp4'):
        final name1080Duplicate = DesktopProcessEngine.resolveOutputBaseName(
          customTitle: 'Cancion Genial',
          option: opt1080,
          downloadDir: tempDir.path,
        );
        expect(name1080Duplicate, equals('Cancion Genial [1080p] (1)'));

        // Simulamos que ese duplicado también se guarda
        File('${tempDir.path}/$name1080Duplicate.mp4').writeAsStringSync('dummy content duplicate');

        // 5. Un tercer intento en 1080p debe generar (2)
        final name1080Third = DesktopProcessEngine.resolveOutputBaseName(
          customTitle: 'Cancion Genial',
          option: opt1080,
          downloadDir: tempDir.path,
        );
        expect(name1080Third, equals('Cancion Genial [1080p] (2)'));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
