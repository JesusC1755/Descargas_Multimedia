import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/domain/models/download_destination.dart';
import 'package:media_downloader/domain/models/stream_option.dart';
import 'package:media_downloader/presentation/controllers/download_folders_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory custom;

  setUp(() => custom = Directory.systemTemp.createTempSync('folders_test'));
  tearDown(() => custom.deleteSync(recursive: true));

  test('por defecto usa MediaDownloader/Video y MediaDownloader/Audio', () async {
    SharedPreferences.setMockInitialValues({});
    final folders = DownloadFoldersController();
    expect(await folders.load(), isEmpty);
    final sep = Platform.pathSeparator;
    expect(folders.of(StreamType.video)!.displayPath, endsWith('MediaDownloader${sep}Video'));
    expect(folders.of(StreamType.audioOnly)!.displayPath, endsWith('MediaDownloader${sep}Audio'));
    expect(folders.isDefault(StreamType.video), isTrue);
  });

  test('la carpeta personalizada de la v1.1 pasa a video y audio', () async {
    final legacy = DownloadDestination(displayPath: custom.path);
    SharedPreferences.setMockInitialValues({'download_destination': legacy.toJson()});
    final folders = DownloadFoldersController();
    await folders.load();
    expect(folders.of(StreamType.video), legacy);
    expect(folders.of(StreamType.audioOnly), legacy);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('download_destination'), isFalse);
  });

  test('una carpeta que ya no existe vuelve a la predeterminada y se avisa', () async {
    final gone = DownloadDestination(displayPath: '${custom.path}${Platform.pathSeparator}borrada');
    SharedPreferences.setMockInitialValues({'download_destination_audio': gone.toJson()});
    final folders = DownloadFoldersController();
    expect(await folders.load(), [gone.displayPath]);
    expect(folders.isDefault(StreamType.audioOnly), isTrue);
  });

  test('restablecer vuelve a la predeterminada y borra la preferencia', () async {
    SharedPreferences.setMockInitialValues({
      'download_destination_video': DownloadDestination(displayPath: custom.path).toJson(),
    });
    final folders = DownloadFoldersController();
    await folders.load();
    expect(folders.isDefault(StreamType.video), isFalse);
    await folders.reset(StreamType.video);
    expect(folders.isDefault(StreamType.video), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('download_destination_video'), isFalse);
  });
}
