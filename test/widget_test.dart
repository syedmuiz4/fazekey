import 'package:flutter_test/flutter_test.dart';
import 'package:fazekey/main.dart' as app;

void main() {
  test('FaceKey project smoke test', () {
    expect('FaceKey'.isNotEmpty, isTrue);
    expect(app.FaceKeyApp, isNotNull);
  });
}
