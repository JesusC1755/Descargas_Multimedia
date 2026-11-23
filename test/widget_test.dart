import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MediaDownloaderApp());
    // El fondo animado nunca "se asienta": avanzar un tiempo fijo en lugar de pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Analizar'), findsOneWidget);
    expect(find.text('Carpeta de destino'), findsOneWidget);
  });
}
