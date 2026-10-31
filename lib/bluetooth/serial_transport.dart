import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import '../core/obd/obd_transport.dart';

/// Canal Bluetooth clássico (SPP) até o adaptador ELM327. É o ÚNICO ponto do núcleo que conhece
/// a biblioteca `flutter_bluetooth_serial`: trocá-la exige mexer só aqui.
class SerialObdTransport implements ObdTransport {
  SerialObdTransport._(this._connection);

  final BluetoothConnection _connection;

  static Future<SerialObdTransport> connect(String address) async {
    final BluetoothConnection connection = await BluetoothConnection.toAddress(address);
    return SerialObdTransport._(connection);
  }

  bool get isConnected => _connection.isConnected;

  @override
  Stream<List<int>> get input => _connection.input!;

  @override
  Future<void> write(List<int> bytes) async {
    _connection.output.add(Uint8List.fromList(bytes));
    await _connection.output.allSent;
  }

  @override
  Future<void> close() async {
    await _connection.close();
  }
}
