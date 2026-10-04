import 'package:flutter_test/flutter_test.dart';
import 'package:media_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MediaDownloaderApp());
    await tester.pumpAndSettle();
    expect(find.text('Media Downloader Desktop'), findsOneWidget);
  });
}
