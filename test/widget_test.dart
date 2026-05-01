import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fazekey/main.dart' as app;

void main() {
  test('FaceKey project smoke test', () {
    expect('FaceKey'.isNotEmpty, isTrue);
    expect(app.FaceKeyApp, isNotNull);
  });

  test('logo asset is bundled', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final data = await rootBundle.load('assets/images/logo2.png');

    expect(data.lengthInBytes, greaterThan(0));
  });

  testWidgets('logo image renders from asset path', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Image.asset('assets/images/logo2.png'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
