import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/sync/outbox.dart';
import 'http_telemetry_api.dart';

class BackendException implements Exception {
  BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UserInfo {
  const UserInfo({required this.id, required this.email, required this.role});

  final String id;
  final String email;
  final String role;

  bool get canRegisterVehicles => role == 'admin' || role == 'mechanic';
}

class VehicleInfo {
  const VehicleInfo({required this.id, required this.plate, this.model});

  final String id;
  final String plate;
  final String? model;

  String get label => model == null || model!.isEmpty ? plate : '$plate · $model';
}

class LoginResult {
  const LoginResult({required this.token, required this.user});

  final String token;
  final UserInfo user;
}

/// Login e cadastro/lista de veículos.
class BackendClient {
  BackendClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final TokenProvider tokenProvider;
  final Duration timeout;
  final http.Client _client;

  Future<LoginResult> login(String email, String password) async {
    final Map<String, Object?> json = await _call(
      'POST',
      '/api/auth/login',
      body: <String, Object?>{'email': email.trim(), 'password': password},
      authenticated: false,
    ) as Map<String, Object?>;
    final Map<String, Object?> user = json['user']! as Map<String, Object?>;
    return LoginResult(
      token: json['token']! as String,
      user: UserInfo(id: user['id']! as String, email: user['email']! as String, role: user['role']! as String),
    );
  }

  Future<List<VehicleInfo>> vehicles() async {
    final List<Object?> list = await _call('GET', '/api/vehicles') as List<Object?>;
    return <VehicleInfo>[
      for (final Object? item in list) _vehicleFromJson(item! as Map<String, Object?>),
    ];
  }

  static VehicleInfo _vehicleFromJson(Map<String, Object?> json) {
    return VehicleInfo(id: json['id']! as String, plate: json['plate']! as String, model: json['model'] as String?);
  }

  Future<VehicleInfo> createVehicle({required String plate, String? model}) async {
    final Map<String, Object?> json = await _call(
      'POST',
      '/api/vehicles',
      body: <String, Object?>{'plate': plate, if (model != null && model.isNotEmpty) 'model': model},
    ) as Map<String, Object?>;
    return _vehicleFromJson(json);
  }

  Future<Object?> _call(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final http.Request request = http.Request(method, Uri.parse('$baseUrl$path'));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final String? token = await tokenProvider();
      if (token == null) throw const ApiUnauthorizedException();
      request.headers['Authorization'] = 'Bearer $token';
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw BackendException('O servidor demorou para responder.');
    } on IOException {
      throw BackendException('Sem conexão com o servidor. Verifique a internet do celular.');
    } on http.ClientException {
      throw BackendException('Sem conexão com o servidor. Verifique a internet do celular.');
    }

    Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    if (response.statusCode == 401 && authenticated) throw const ApiUnauthorizedException();

    String message = 'Erro ${response.statusCode} no servidor.';
    if (decoded is Map<String, Object?> && decoded['message'] is String) {
      message = decoded['message']! as String;
    }
    throw BackendException(message);
  }
}
