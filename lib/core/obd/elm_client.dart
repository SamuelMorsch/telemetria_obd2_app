import 'dart:async';
import 'dart:convert';

import 'elm_parser.dart';
import 'obd_exceptions.dart';
import 'obd_transport.dart';

/// Envia comandos ao ELM327 e espera a resposta completa (que termina com o prompt ">").
/// Um comando por vez.
class ElmClient {
  ElmClient(this._transport, {this.defaultTimeout = const Duration(seconds: 3)}) {
    _subscription = _transport.input.listen(_onData, onDone: _onClosed, onError: (Object _) => _onClosed());
  }

  final ObdTransport _transport;

  /// Tempo máximo de espera quando o comando não define o seu.
  final Duration defaultTimeout;
  late final StreamSubscription<List<int>> _subscription;
  final StringBuffer _buffer = StringBuffer();
  Completer<String>? _pending;
  bool _closed = false;

  /// O canal terminou (o Bluetooth caiu). Quem espera uma resposta é avisado na hora, e os próximos
  /// comandos falham sem esperar o tempo limite.
  void _onClosed() {
    _closed = true;
    final Completer<String>? pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(ObdConnectionException(_closedMessage));
    }
  }

  static const String _closedMessage = 'A conexão Bluetooth com o adaptador foi encerrada';

  void _onData(List<int> data) {
    _buffer.write(latin1.decode(data, allowInvalid: true));
    final String text = _buffer.toString();
    final int end = text.indexOf('>');
    if (end < 0) return; // resposta ainda incompleta

    final Completer<String>? pending = _pending;
    _buffer.clear();
    final String rest = text.substring(end + 1);
    if (rest.isNotEmpty) _buffer.write(rest);
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.complete(text.substring(0, end));
    }
  }

  /// Envia [command] e devolve as linhas da resposta, sem eco nem prompt.
  /// Lança [ElmTimeoutException] se não houver resposta, [ElmErrorException] em erro grave e
  /// [ObdConnectionException] se o Bluetooth caiu. "NO DATA" não lança: vem nas linhas (veja `isNoData`).
  Future<List<String>> send(String command, {Duration? timeout}) async {
    if (_closed) throw ObdConnectionException(_closedMessage);
    if (_pending != null) {
      throw StateError('Já existe um comando em andamento');
    }
    _buffer.clear();
    final Completer<String> completer = Completer<String>();
    _pending = completer;
    final Future<String> response = completer.future.timeout(timeout ?? defaultTimeout);
    response.ignore(); // se a conexão cair durante a escrita, o erro é entregue abaixo, sem aviso solto
    try {
      try {
        await _transport.write(latin1.encode('$command\r')).timeout(timeout ?? defaultTimeout);
      } catch (e) {
        // Escrever num Bluetooth desconectado lança um erro da biblioteca (ou fica pendurado), que não é do tipo OBD.
        throw ObdConnectionException('Falha ao enviar o comando $command ao adaptador: $e');
      }
      final String raw = await response;
      final List<String> lines = cleanLines(raw, command: command);
      final String? error = fatalError(lines);
      if (error != null) throw ElmErrorException(command, error);
      return lines;
    } on TimeoutException {
      throw ElmTimeoutException(command);
    } finally {
      if (identical(_pending, completer)) _pending = null;
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _transport.close();
  }
}
