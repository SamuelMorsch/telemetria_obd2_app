import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class OBDService {
  BluetoothConnection? _connection;
  String _buffer = '';
  bool _isPolling = false;
  Completer<String>? _commandCompleter;

  final ValueNotifier<int> rpm = ValueNotifier<int>(0);
  final ValueNotifier<int> speed = ValueNotifier<int>(0);
  final ValueNotifier<String> connectionStatus = ValueNotifier<String>("Desconectado");
  final ValueNotifier<String> rawDebug = ValueNotifier<String>("Aguardando dados...");

  Future<void> connect(BluetoothDevice device) async {
    try {
      connectionStatus.value = "Conectando fisicamente...";
      _connection = await BluetoothConnection.toAddress(device.address);

      _connection!.input!.listen(_onDataReceived).onDone(() {
        disconnect();
      });

      await _initializeELM327();
    } catch (e) {
      connectionStatus.value = "Falha de Conexão";
      debugPrint("Erro grave no Bluetooth: $e");
    }
  }

  void disconnect() {
    _isPolling = false;
    _connection?.close();
    connectionStatus.value = "Desconectado";
    rpm.value = 0;
    speed.value = 0;
    rawDebug.value = "Aguardando dados...";
  }

  Future<String> _sendAndAwaitResponse(String command, {int timeoutSeconds = 15}) async {
    if (_connection == null || !_connection!.isConnected) return "";

    _commandCompleter = Completer<String>();
    _buffer = '';
    _connection!.output.add(ascii.encode("$command\r"));

    try {
      return await _commandCompleter!.future.timeout(Duration(seconds: timeoutSeconds));
    } catch (e) {
      return "TIMEOUT";
    }
  }

  void _onDataReceived(Uint8List data) {
    String incoming = ascii.decode(data);
    _buffer += incoming;

    if (_buffer.contains('>')) {
      String response = _buffer.replaceAll('>', '').trim();
      _buffer = '';

      if (_commandCompleter != null && !_commandCompleter!.isCompleted) {
        _commandCompleter!.complete(response);
      }
    }
  }

  Future<void> _initializeELM327() async {
    connectionStatus.value = "Reiniciando ELM327...";
    await _sendAndAwaitResponse("AT Z", timeoutSeconds: 3);
    await Future.delayed(const Duration(milliseconds: 500));

    connectionStatus.value = "Limpando formatações...";
    await _sendAndAwaitResponse("AT E0");
    await _sendAndAwaitResponse("AT L0");
    await _sendAndAwaitResponse("AT S0");
    await _sendAndAwaitResponse("AT AT 1");

    List<String> protocolos = ['6', '3', '4', '5', '7', '1', '2', '8', '9'];
    bool conectado = false;

    for (String p in protocolos) {
      connectionStatus.value = "Testando protocolo SP $p...";
      await _sendAndAwaitResponse("AT SP $p", timeoutSeconds: 2);

      String resposta = await _sendAndAwaitResponse("0100", timeoutSeconds: 4);
      String limpa = resposta.replaceAll(' ', '').replaceAll('\r', '').replaceAll('\n', '').toUpperCase();

      if (limpa.contains("4100")) {
        conectado = true;
        connectionStatus.value = "Conectado no protocolo $p!";
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (conectado) {
      await Future.delayed(const Duration(seconds: 1));
      connectionStatus.value = "Lendo telemetria ao vivo";
      _startPolling();
    } else {
      connectionStatus.value = "Falha: Nenhum protocolo compatível.";
      rawDebug.value = "ECU não respondeu a nenhum dos 9 protocolos.";
    }
  }

  void _startPolling() async {
    _isPolling = true;
    bool askRpm = true;

    while (_isPolling && _connection != null && _connection!.isConnected) {
      String cmd = askRpm ? "010C" : "010D";
      String response = await _sendAndAwaitResponse(cmd, timeoutSeconds: 15);

      _parseOBDResponse(response);

      askRpm = !askRpm;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _parseOBDResponse(String response) {
    rawDebug.value = response.replaceAll('\r', ' ').replaceAll('\n', ' ');

    try {
      String cleanHex = response.replaceAll(' ', '').replaceAll('\r', '').replaceAll('\n', '').toUpperCase();

      if (cleanHex.contains("NODATA") || cleanHex.contains("SEARCHING")) return;

      if (cleanHex.contains("410C")) {
        int idx = cleanHex.indexOf("410C");
        if (cleanHex.length >= idx + 8) {
          String aHex = cleanHex.substring(idx + 4, idx + 6);
          String bHex = cleanHex.substring(idx + 6, idx + 8);
          int a = int.parse(aHex, radix: 16);
          int b = int.parse(bHex, radix: 16);
          rpm.value = ((a * 256) + b) ~/ 4;
        }
      }
      else if (cleanHex.contains("410D")) {
        int idx = cleanHex.indexOf("410D");
        if (cleanHex.length >= idx + 6) {
          String aHex = cleanHex.substring(idx + 4, idx + 6);
          int a = int.parse(aHex, radix: 16);
          speed.value = a;
        }
      }
    } catch (e) {
      rawDebug.value = "ERRO DE PARSE: $e";
    }
  }
}