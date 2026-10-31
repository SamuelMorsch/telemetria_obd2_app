import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/capture/uuid.dart';

void main() {
  test('gera UUID v4 válido, e diferente a cada chamada', () {
    final RegExp pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final Set<String> seen = <String>{};
    for (int i = 0; i < 200; i++) {
      final String id = generateUuidV4();
      expect(pattern.hasMatch(id), isTrue, reason: id);
      seen.add(id);
    }
    expect(seen.length, 200);
  });

  test('com a mesma semente gera o mesmo UUID (determinístico para testes)', () {
    expect(generateUuidV4(Random(7)), generateUuidV4(Random(7)));
  });
}
