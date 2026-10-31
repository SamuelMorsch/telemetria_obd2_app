import 'package:flutter/foundation.dart';

import 'bluetooth/bluetooth_devices.dart';
import 'bluetooth/serial_transport.dart';
import 'capture/capture_controller.dart';
import 'config.dart';
import 'core/obd/elm_client.dart';
import 'core/obd/obd_reader.dart';
import 'core/sync/outbox_syncer.dart';
import 'data/app_database.dart';
import 'data/backend_client.dart';
import 'data/http_telemetry_api.dart';
import 'data/local_store.dart';

/// Reúne as peças do app (banco, servidor, Bluetooth) e guarda o login.
/// As telas falam só com este objeto.
class AppServices extends ChangeNotifier {
  AppServices._();

  static final AppServices instance = AppServices._();

  late final LocalStore store;
  late final BackendClient backend;
  late final OutboxSyncer syncer;
  final BluetoothDevices bluetooth = const BluetoothDevices();

  String? _token;
  UserInfo? user;
  bool _initialized = false;

  bool get isLoggedIn => _token != null && user != null;

  Future<void> init() async {
    if (_initialized) return;
    store = LocalStore(AppDatabase.instance);
    backend = BackendClient(baseUrl: kApiBaseUrl, tokenProvider: () async => _token);
    syncer = OutboxSyncer(
      store: store,
      api: HttpTelemetryApi(baseUrl: kApiBaseUrl, tokenProvider: () async => _token),
    );

    // Se o app fechou no meio de uma captura, encerra essa sessão no horário da última leitura.
    await store.closeOrphanSessions();

    _token = await store.getValue('token');
    final String? id = await store.getValue('user_id');
    final String? email = await store.getValue('user_email');
    final String? role = await store.getValue('user_role');
    if (_token != null && id != null && email != null && role != null) {
      user = UserInfo(id: id, email: email, role: role);
    } else {
      _token = null;
    }
    _initialized = true;
  }

  Future<void> login(String email, String password) async {
    final LoginResult result = await backend.login(email, password);
    _token = result.token;
    user = result.user;
    await store.setValue('token', result.token);
    await store.setValue('user_id', result.user.id);
    await store.setValue('user_email', result.user.email);
    await store.setValue('user_role', result.user.role);
    notifyListeners();
  }

  /// Sai da conta. O que estava na fila de envio continua no celular e segue depois de entrar de novo.
  Future<void> logout() async {
    _token = null;
    user = null;
    await store.removeValue('token');
    await store.removeValue('user_id');
    await store.removeValue('user_email');
    await store.removeValue('user_role');
    notifyListeners();
  }

  CaptureController createCaptureController() {
    return CaptureController(
      store: store,
      syncer: syncer,
      linkFactory: _connectLink,
      appVersion: kAppVersion,
    );
  }

  /// Abre o Bluetooth até o adaptador e o inicializa.
  Future<ObdLink> _connectLink(String address) async {
    final SerialObdTransport transport = await SerialObdTransport.connect(address);
    final ElmClient client = ElmClient(transport);
    final ObdReader reader = ObdReader(client);
    try {
      await reader.initialize();
    } catch (_) {
      await client.close();
      rethrow;
    }
    return ObdLink(reader: reader, close: client.close);
  }
}
