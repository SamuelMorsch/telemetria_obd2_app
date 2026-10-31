import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/models.dart';
import '../core/obd/obd_exceptions.dart';
import '../core/obd/obd_reader.dart';
import '../core/sync/outbox.dart';
import '../core/sync/outbox_syncer.dart';
import 'capture_store.dart';
import 'uuid.dart';

enum CaptureStatus { idle, connecting, capturing, stopping, error }

/// Conexão já aberta e inicializada com o veículo, e como fechá-la.
class ObdLink {
  const ObdLink({required this.reader, required this.close});

  final ObdReader reader;
  final Future<void> Function() close;
}

/// Abre o Bluetooth, inicializa o adaptador e devolve o link. Em produção usa o Bluetooth;
/// nos testes, um adaptador de mentira.
typedef LinkFactory = Future<ObdLink> Function(String deviceAddress);

/// Coordena a captura: lê o veículo em ciclos, grava cada leitura no celular, envia ao servidor
/// em segundo plano e encerra a sessão. A tela só observa este objeto.
class CaptureController extends ChangeNotifier {
  CaptureController({
    required this.store,
    required this.syncer,
    required this.linkFactory,
    DateTime Function()? clock,
    String Function()? idGenerator,
    this.appVersion,
    this.syncEvery = const Duration(seconds: 5),
    this.dtcEvery = const Duration(seconds: 30),
    this.maxConsecutiveFailures = 3,
  })  : _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? generateUuidV4;

  final CaptureStore store;
  final OutboxSyncer syncer;
  final LinkFactory linkFactory;
  final String? appVersion;
  final Duration syncEvery;
  final Duration dtcEvery;
  final int maxConsecutiveFailures;
  final DateTime Function() _clock;
  final String Function() _newId;

  CaptureStatus status = CaptureStatus.idle;
  String? errorMessage;
  String? sessionId;
  ObdValues? latest;
  List<Dtc> dtcs = <Dtc>[];

  /// Diagnóstico da leitura de códigos de falha (aparece na tela de captura).
  int dtcReadsDone = 0;
  DateTime? lastDtcReadAt;
  String? lastDtcError;
  String lastDtcRaw = '';
  int readingsCaptured = 0;
  int readingsSent = 0;
  int readingsDiscarded = 0;
  double readingsPerSecond = 0;
  SyncResult? lastSync;
  DateTime? lastSyncAt;
  String? lastSyncError;

  ObdLink? _link;
  Future<void>? _loop;
  bool _syncing = false;
  bool _forceDtcRead = false;
  int _seq = 0;
  DateTime? _lastDtcAt;
  final Set<String> _seenDtcs = <String>{};
  final Stopwatch _clockWatch = Stopwatch();

  /// Leituras capturadas que ainda não chegaram ao servidor.
  int get pendingReadings {
    final int pending = readingsCaptured - readingsSent - readingsDiscarded;
    return pending < 0 ? 0 : pending;
  }

  bool get isActive =>
      status == CaptureStatus.connecting || status == CaptureStatus.capturing || status == CaptureStatus.stopping;

  /// Conecta ao adaptador e começa a capturar. Em caso de falha, vai para o estado de erro
  /// (sem criar sessão).
  Future<void> start({
    required String vehicleId,
    required String deviceAddress,
    String source = 'obd',
  }) async {
    if (isActive) return;
    _reset();
    status = CaptureStatus.connecting;
    notifyListeners();

    try {
      _link = await linkFactory(deviceAddress);
    } catch (e) {
      status = CaptureStatus.error;
      errorMessage = e is ObdException ? e.message : 'Não foi possível conectar ao adaptador: $e';
      notifyListeners();
      return;
    }

    final String id = _newId();
    sessionId = id;
    await store.createSession(
      PendingSession(
        id: id,
        vehicleId: vehicleId,
        startedAt: _clock(),
        source: source,
        appVersion: appVersion,
      ),
    );
    status = CaptureStatus.capturing;
    _clockWatch
      ..reset()
      ..start();
    notifyListeners();
    _loop = _run();
  }

  /// Pede para o ciclo atual terminar, encerra a sessão e envia o que sobrou.
  Future<void> stop() async {
    if (status != CaptureStatus.capturing) return;
    status = CaptureStatus.stopping;
    notifyListeners();
    await _loop;
  }

  /// Lê os códigos de falha na próxima oportunidade (o adaptador atende um comando por vez).
  void readDtcsSoon() => _forceDtcRead = true;

  /// Tenta enviar agora o que está na fila (botão "Enviar agora").
  Future<void> syncNow() => _sync();

  void _reset() {
    status = CaptureStatus.idle;
    errorMessage = null;
    sessionId = null;
    latest = null;
    dtcs = <Dtc>[];
    dtcReadsDone = 0;
    lastDtcReadAt = null;
    lastDtcError = null;
    lastDtcRaw = '';
    readingsCaptured = 0;
    readingsSent = 0;
    readingsDiscarded = 0;
    readingsPerSecond = 0;
    lastSync = null;
    lastSyncAt = null;
    lastSyncError = null;
    _seq = 0;
    _lastDtcAt = null;
    _seenDtcs.clear();
    _forceDtcRead = false;
  }

  Future<void> _run() async {
    final ObdReader reader = _link!.reader;
    int cycle = 0;
    int failures = 0;
    String? error;

    while (status == CaptureStatus.capturing) {
      try {
        final DateTime now = _clock();
        if (_forceDtcRead || _lastDtcAt == null || now.difference(_lastDtcAt!) >= dtcEvery) {
          _forceDtcRead = false;
          await _readDtcsSafely(reader, now);
        }

        final ObdValues values = await reader.readCycle(cycle++);
        final Reading reading = Reading(seq: _seq++, time: _clock(), values: values);
        await store.addReading(sessionId!, reading);
        latest = values;
        readingsCaptured++;
        failures = 0;
        final int ms = _clockWatch.elapsedMilliseconds;
        if (ms > 0) readingsPerSecond = readingsCaptured * 1000 / ms;
        notifyListeners();
      } on ObdException catch (e) {
        failures++;
        if (failures >= maxConsecutiveFailures) {
          error = 'Conexão com o adaptador perdida (${e.message}).';
          break;
        }
      } catch (e) {
        error = 'Erro inesperado na captura: $e';
        break;
      }

      final DateTime? last = lastSyncAt;
      if (!_syncing && (last == null || _clock().difference(last) >= syncEvery)) {
        unawaited(_sync());
      }
      await Future<void>.delayed(Duration.zero); // cede a vez para a tela e para o envio
    }

    await _finalize(error);
  }

  /// Lê os códigos de falha SEM afetar a captura: um erro aqui (adaptador sem modo 07, resposta
  /// lenta, ruído) não conta como perda de conexão e não é repetido a cada ciclo, só no próximo
  /// intervalo. A tensão e a rotação, que são o objetivo do projeto, continuam sendo lidas.
  Future<void> _readDtcsSafely(ObdReader reader, DateTime now) async {
    _lastDtcAt = now; // mesmo se falhar, só tenta de novo daqui a `dtcEvery` (ou no "Ler agora")
    try {
      final List<Dtc> found = await reader.readDtcs();
      dtcs = found;
      lastDtcError = null;
      for (final Dtc dtc in found) {
        if (_seenDtcs.add('${dtc.code}/${dtc.status.apiName}')) {
          await store.addDtc(sessionId!, dtc, now);
        }
      }
    } on ObdException catch (e) {
      lastDtcError = e.message;
    } finally {
      dtcReadsDone++;
      lastDtcReadAt = now;
      lastDtcRaw = reader.lastDtcRaw;
      notifyListeners();
    }
  }

  Future<void> _finalize(String? error) async {
    final ObdLink? link = _link;
    _link = null;
    final String? id = sessionId;
    if (id != null) await store.endSession(id, _clock());

    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _sync();

    try {
      await link?.close();
    } catch (_) {
      // já estava desconectado
    }
    status = error == null ? CaptureStatus.idle : CaptureStatus.error;
    errorMessage = error;
    notifyListeners();
  }

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final SyncResult result = await syncer.syncOnce();
      lastSync = result;
      lastSyncAt = _clock();
      lastSyncError = null;
      readingsSent += result.readingsSent;
      readingsDiscarded += result.discarded;
    } catch (e) {
      lastSyncAt = _clock();
      lastSyncError = e.toString();
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }
}
