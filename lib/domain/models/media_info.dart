import 'stream_option.dart';

class MediaInfo {
  final String url;
  final String title;
  final String? uploader;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final List<StreamOption> videoOptions;
  final List<StreamOption> audioOptions;

  const MediaInfo({
    required this.url,
    required this.title,
    this.uploader,
    this.thumbnailUrl,
    this.durationSeconds,
    required this.videoOptions,
    required this.audioOptions,
  });
}
