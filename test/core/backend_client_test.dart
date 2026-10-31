import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:telemetria_obd2_app/core/sync/outbox.dart';
import 'package:telemetria_obd2_app/data/backend_client.dart';

BackendClient clientWith(MockClient mock, {String? token = 'tok'}) =>
    BackendClient(baseUrl: 'https://exemplo.test', tokenProvider: () async => token, client: mock);

void main() {
  test('login devolve o token e o usuário; envia e-mail sem espaços e sem Authorization', () async {
    late http.Request seen;
    final BackendClient client = clientWith(MockClient((http.Request request) async {
      seen = request;
      return http.Response(
        jsonEncode(<String, Object?>{
          'token': 'abc',
          'user': <String, Object?>{'id': 'u1', 'email': 'a@b.com', 'role': 'mechanic'},
        }),
        200,
      );
    }));

    final LoginResult result = await client.login('  a@b.com ', 'senha-forte-123');

    expect(result.token, 'abc');
    expect(result.user.role, 'mechanic');
    expect(result.user.canRegisterVehicles, isTrue);
    expect(jsonDecode(seen.body), <String, Object?>{'email': 'a@b.com', 'password': 'senha-forte-123'});
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('senha errada: mostra a mensagem da API', () async {
    final BackendClient client = clientWith(MockClient((http.Request r) async => http.Response(
          jsonEncode(<String, Object?>{'error': 'invalid_credentials', 'message': 'E-mail ou senha inválidos.'}),
          401,
        )));

    await expectLater(
      client.login('a@b.com', 'x'),
      throwsA(isA<BackendException>().having((BackendException e) => e.message, 'message', 'E-mail ou senha inválidos.')),
    );
  });

  test('lista de veículos', () async {
    final BackendClient client = clientWith(MockClient((http.Request request) async {
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode(<Object?>[
          <String, Object?>{'id': 'v1', 'plate': 'ABC1D23', 'model': 'Fiat Uno'},
          <String, Object?>{'id': 'v2', 'plate': 'XYZ9K88', 'model': null},
        ]),
        200,
      );
    }));

    final List<VehicleInfo> vehicles = await client.vehicles();

    expect(vehicles.map((VehicleInfo v) => v.label), <String>['ABC1D23 · Fiat Uno', 'XYZ9K88']);
  });

  test('cadastra veículo', () async {
    late http.Request seen;
    final BackendClient client = clientWith(MockClient((http.Request request) async {
      seen = request;
      return http.Response(jsonEncode(<String, Object?>{'id': 'v9', 'plate': 'ABC1D23', 'model': 'Uno'}), 201);
    }));

    final VehicleInfo vehicle = await client.createVehicle(plate: 'abc-1d23', model: 'Uno');

    expect(vehicle.id, 'v9');
    expect(jsonDecode(seen.body), <String, Object?>{'plate': 'abc-1d23', 'model': 'Uno'});
  });

  test('token expirado em rota protegida vira ApiUnauthorizedException', () async {
    final BackendClient client = clientWith(MockClient((http.Request r) async => http.Response('{}', 401)));
    await expectLater(client.vehicles(), throwsA(isA<ApiUnauthorizedException>()));
  });

  test('sem rede: mensagem em português', () async {
    final BackendClient client =
        clientWith(MockClient((http.Request r) async => throw const SocketException('sem rede')));

    await expectLater(
      client.login('a@b.com', 'x'),
      throwsA(isA<BackendException>().having((BackendException e) => e.message, 'message', contains('Sem conexão'))),
    );
  });

  test('erro 403 do servidor mostra a mensagem dele', () async {
    final BackendClient client = clientWith(MockClient((http.Request r) async => http.Response(
          jsonEncode(<String, Object?>{'error': 'forbidden', 'message': 'Sem permissão para esta operação.'}),
          403,
        )));

    await expectLater(
      client.createVehicle(plate: 'ABC1D23'),
      throwsA(isA<BackendException>().having((BackendException e) => e.message, 'message', contains('Sem permissão'))),
    );
  });
}
