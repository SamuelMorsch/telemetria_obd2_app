import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/sync/outbox.dart';
import 'package:telemetria_obd2_app/data/http_telemetry_api.dart';

final Reading reading = Reading(
  seq: 3,
  time: DateTime.utc(2026, 10, 14, 12, 0, 3),
  values: const ObdValues(batteryVoltage: 14.2, rpm: 2500),
);

HttpTelemetryApi apiWith(MockClient client, {String? token = 'tok123'}) => HttpTelemetryApi(
      baseUrl: 'https://exemplo.test',
      tokenProvider: () async => token,
      client: client,
    );

void main() {
  test('envia o lote para a rota certa com o token e o JSON esperado pela API', () async {
    late http.BaseRequest seen;
    String? body;
    final HttpTelemetryApi api = apiWith(MockClient((http.Request request) async {
      seen = request;
      body = request.body;
      return http.Response('{}', 201);
    }));

    await api.sendReadings('sess-1', <Reading>[reading]);

    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'https://exemplo.test/api/sessions/sess-1/readings');
    expect(seen.headers['Authorization'], 'Bearer tok123');
    expect(jsonDecode(body!), <String, Object?>{
      'readings': <Object?>[
        <String, Object?>{'seq': 3, 'time': '2026-10-14T12:00:03.000Z', 'battery_voltage': 14.2, 'rpm': 2500},
      ],
    });
  });

  test('abre a sessão com id, veículo, horário UTC e origem', () async {
    String? body;
    final HttpTelemetryApi api = apiWith(MockClient((http.Request request) async {
      body = request.body;
      return http.Response('{}', 200); // 200 = já existia: também é sucesso
    }));

    await api.openSession(PendingSession(
      id: 's1',
      vehicleId: 'v1',
      startedAt: DateTime.utc(2026, 10, 14, 12),
      source: 'obd',
      appVersion: '2.0.0',
    ));

    expect(jsonDecode(body!), <String, Object?>{
      'id': 's1',
      'vehicle_id': 'v1',
      'started_at': '2026-10-14T12:00:00.000Z',
      'source': 'obd',
      'app_version': '2.0.0',
    });
  });

  test('códigos de falha e encerramento usam as rotas corretas', () async {
    final List<String> calls = <String>[];
    final HttpTelemetryApi api = apiWith(MockClient((http.Request request) async {
      calls.add('${request.method} ${request.url.path}');
      return http.Response('{}', 201);
    }));

    await api.sendDtcs('s1', <PendingDtc>[
      PendingDtc(id: 1, dtc: const Dtc(code: 'P0043', status: DtcStatus.stored), detectedAt: DateTime.utc(2026, 10, 14)),
    ]);
    await api.endSession('s1', DateTime.utc(2026, 10, 14, 13));

    expect(calls, <String>['POST /api/sessions/s1/dtcs', 'PATCH /api/sessions/s1/end']);
  });

  test('401 vira ApiUnauthorizedException; sem token também', () async {
    final HttpTelemetryApi api = apiWith(MockClient((http.Request r) async => http.Response('{}', 401)));
    await expectLater(api.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnauthorizedException>()));

    final HttpTelemetryApi noToken =
        apiWith(MockClient((http.Request r) async => http.Response('{}', 200)), token: null);
    await expectLater(noToken.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnauthorizedException>()));
  });

  test('429 e 5xx são "tentar depois"; 400 é recusa definitiva', () async {
    for (final int status in <int>[429, 500, 502, 503]) {
      final HttpTelemetryApi api = apiWith(MockClient((http.Request r) async => http.Response('{}', status)));
      await expectLater(api.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnavailableException>()));
    }
    final HttpTelemetryApi bad = apiWith(MockClient((http.Request r) async => http.Response('{}', 400)));
    await expectLater(
      bad.sendReadings('s', <Reading>[reading]),
      throwsA(isA<ApiRejectedException>().having((ApiRejectedException e) => e.status, 'status', 400)),
    );
  });

  test('404 em leituras NÃO descarta os dados (tenta depois); 404 ao abrir sessão é recusa', () async {
    final HttpTelemetryApi api = apiWith(MockClient((http.Request r) async => http.Response('{}', 404)));

    await expectLater(api.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnavailableException>()));
    await expectLater(
      api.openSession(PendingSession(id: 's', vehicleId: 'v', startedAt: DateTime.utc(2026), source: 'obd')),
      throwsA(isA<ApiRejectedException>()),
    );
  });

  test('sem rede ou tempo esgotado viram ApiUnavailableException', () async {
    final HttpTelemetryApi offline =
        apiWith(MockClient((http.Request r) async => throw const SocketException('sem rede')));
    await expectLater(offline.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnavailableException>()));

    final HttpTelemetryApi broken =
        apiWith(MockClient((http.Request r) async => throw http.ClientException('falhou')));
    await expectLater(broken.sendReadings('s', <Reading>[reading]), throwsA(isA<ApiUnavailableException>()));
  });
}
