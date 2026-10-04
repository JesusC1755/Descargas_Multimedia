import 'dart:async';
import 'package:flutter/material.dart';
import 'core/logging/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/home_screen.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) => talker.handle(details.exception, details.stack);

    runApp(const MediaDownloaderApp());
  }, (error, stack) {
    talker.handle(error, stack);
  });
}

class MediaDownloaderApp extends StatefulWidget {
  const MediaDownloaderApp({super.key});

  @override
  State<MediaDownloaderApp> createState() => _MediaDownloaderAppState();
}

class _MediaDownloaderAppState extends State<MediaDownloaderApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Downloader Desktop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _themeMode,
      home: HomeScreen(
        onToggleTheme: _toggleTheme,
        isDarkMode: _themeMode == ThemeMode.dark,
      ),
    );
  }
}
