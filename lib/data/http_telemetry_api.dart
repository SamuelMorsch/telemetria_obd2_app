import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../core/sync/outbox.dart';

typedef TokenProvider = Future<String?> Function();

/// Envia as sessões, leituras e códigos de falha à API. Traduz as respostas HTTP para o que
/// o [OutboxSyncer] entende: 401 = login expirado; 429/5xx/sem rede = tentar depois; outros 4xx = recusado.
class HttpTelemetryApi implements TelemetryApi {
  HttpTelemetryApi({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final TokenProvider tokenProvider;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<void> openSession(PendingSession session) {
    return _send('POST', '/api/sessions', <String, Object?>{
      'id': session.id,
      'vehicle_id': session.vehicleId,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'source': session.source,
      if (session.appVersion != null) 'app_version': session.appVersion,
    });
  }

  @override
  Future<void> sendReadings(String sessionId, List<Reading> readings) {
    return _send('POST', '/api/sessions/$sessionId/readings', <String, Object?>{
      'readings': <Map<String, Object?>>[for (final Reading r in readings) r.toApiJson()],
    }, notFoundIsTransient: true);
  }

  @override
  Future<void> sendDtcs(String sessionId, List<PendingDtc> dtcs) {
    return _send('POST', '/api/sessions/$sessionId/dtcs', <String, Object?>{
      'dtcs': <Map<String, Object?>>[
        for (final PendingDtc d in dtcs)
          <String, Object?>{
            'code': d.dtc.code,
            'status': d.dtc.status.apiName,
            'detected_at': d.detectedAt.toUtc().toIso8601String(),
          },
      ],
    }, notFoundIsTransient: true);
  }

  @override
  Future<void> endSession(String sessionId, DateTime endedAt) {
    return _send('PATCH', '/api/sessions/$sessionId/end', <String, Object?>{
      'ended_at': endedAt.toUtc().toIso8601String(),
    }, notFoundIsTransient: true);
  }

  /// `notFoundIsTransient`: um 404 em leituras/códigos/encerramento NÃO descarta os dados
  /// (seria perda silenciosa se o servidor ainda não conhecesse a sessão); tenta de novo depois.
  Future<void> _send(
    String method,
    String path,
    Map<String, Object?> body, {
    bool notFoundIsTransient = false,
  }) async {
    final String? token = await tokenProvider();
    if (token == null) throw const ApiUnauthorizedException();

    final http.Request request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Content-Type'] = 'application/json'
      ..headers['Authorization'] = 'Bearer $token'
      ..body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiUnavailableException();
    } on IOException {
      throw const ApiUnavailableException();
    } on http.ClientException {
      throw const ApiUnavailableException();
    }

    final int status = response.statusCode;
    if (status >= 200 && status < 300) return;
    if (status == 401) throw const ApiUnauthorizedException();
    if (status == 429 || status >= 500) throw const ApiUnavailableException();
    if (status == 404 && notFoundIsTransient) throw const ApiUnavailableException();
    throw ApiRejectedException(status);
  }
}
