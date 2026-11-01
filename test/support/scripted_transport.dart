import 'dart:async';
import 'dart:convert';

import 'package:telemetria_obd2_app/core/obd/obd_transport.dart';

/// Adaptador de mentira: para cada comando recebido, devolve a resposta combinada,
/// em pedaços pequenos (como o Bluetooth faz). Comando sem resposta combinada = silêncio (timeout).
class ScriptedTransport implements ObdTransport {
  ScriptedTransport(this.script, {this.chunkSize = 4});

  final Map<String, String> script;
  final int chunkSize;
  final StreamController<List<int>> _controller = StreamController<List<int>>();
  final List<String> sent = <String>[];

  @override
  Stream<List<int>> get input => _controller.stream;

  @override
  Future<void> write(List<int> bytes) async {
    final String command = latin1.decode(bytes).trim();
    sent.add(command);
    final String? reply = script[command];
    if (reply == null) return;
    final List<int> data = latin1.encode(reply);
    for (int i = 0; i < data.length; i += chunkSize) {
      final int end = i + chunkSize > data.length ? data.length : i + chunkSize;
      _controller.add(data.sublist(i, end));
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Respostas de um carro com CAN (protocolo 6), como o do teste, ligado e em marcha lenta.
Map<String, String> fakeCarScript({String stored = '43 00 00 00 00 00 00', String pending = 'NO DATA'}) {
  return <String, String>{
    'ATZ': 'ELM327 v1.5\r\r>',
    'ATE0': 'OK\r\r>',
    'ATL0': 'OK\r\r>',
    'ATS0': 'OK\r\r>',
    'ATH0': 'OK\r\r>',
    'ATSP0': 'OK\r\r>',
    '0100': 'SEARCHING...\r41 00 BE 3F A8 13\r\r>',
    '0120': '41 20 80 00 00 01\r\r>',
    '0140': '41 40 7A 1C 80 00\r\r>',
    'ATDPN': 'A6\r\r>',
    'ATRV': '14.2V\r\r>',
    '010C': '41 0C 1A F8\r\r>',
    '010D': '41 0D 3C\r\r>',
    '0142': '41 42 38 5C\r\r>',
    '0105': '41 05 7B\r\r>',
    '03': '$stored\r\r>',
    '07': '$pending\r\r>',
    '04': '44\r\r>',
  };
}
