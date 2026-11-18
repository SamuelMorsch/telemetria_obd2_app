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
    this.reconnectBackoff = const Duration(seconds: 2),
    this.reconnectMaxBackoff = const Duration(seconds: 15),
    this.reconnectAttemptTimeout = const Duration(seconds: 25),
    this.reconnectGiveUpAfter = const Duration(minutes: 5),
  })  : _clock = clock ?? DateTime.now,
        _newId = idGenerator ?? generateUuidV4;

  final CaptureStore store;
  final OutboxSyncer syncer;
  final LinkFactory linkFactory;
  final String? appVersion;
  final Duration syncEvery;
  final Duration dtcEvery;
  final int maxConsecutiveFailures;

  /// Espera antes da primeira nova tentativa de conexão; dobra a cada falha, até [reconnectMaxBackoff].
  final Duration reconnectBackoff;
  final Duration reconnectMaxBackoff;

  /// Tempo máximo de uma tentativa de conexão (o Bluetooth pode ficar esperando por muito tempo).
  final Duration reconnectAttemptTimeout;

  /// Sem nenhuma leitura por este tempo, a captura desiste e encerra com erro.
  final Duration reconnectGiveUpAfter;
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

  /// Reconexão automática do Bluetooth. `reconnecting` fica ligado enquanto o app tenta voltar.
  bool reconnecting = false;
  int reconnectAttempts = 0;
  int reconnections = 0;
  DateTime? lastReconnectAt;
  String? lastLinkError;

  ObdLink? _link;
  String? _deviceAddress;
  DateTime? _lastReadingAt;
  String? _reconnectFailure;
  final Stopwatch _sinceLastReading = Stopwatch();
  Completer<void> _stopSignal = Completer<void>();
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

  /// Horário da última leitura gravada (mostra a "idade" dos valores durante uma reconexão).
  DateTime? get lastReadingAt => _lastReadingAt;

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
    _deviceAddress = deviceAddress;
    status = CaptureStatus.connecting;
    notifyListeners();

    try {
      _link = await linkFactory(deviceAddress);
    } catch (e) {
      status = CaptureStatus.error;
      errorMessage = e is ObdException ? e.message : 'Não foi possível conectar ao adaptador: ${describeError(e)}';
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
    _sinceLastReading
      ..reset()
      ..start();
    notifyListeners();
    _loop = _run();
  }

  /// Pede para o ciclo atual terminar, encerra a sessão e envia o que sobrou.
  Future<void> stop() async {
    if (status != CaptureStatus.capturing) return;
    status = CaptureStatus.stopping;
    if (!_stopSignal.isCompleted) _stopSignal.complete();
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
    reconnecting = false;
    reconnectAttempts = 0;
    reconnections = 0;
    lastReconnectAt = null;
    lastLinkError = null;
    _lastReadingAt = null;
    _reconnectFailure = null;
    _stopSignal = Completer<void>();
  }

  Future<void> _run() async {
    ObdReader reader = _link!.reader;
    int cycle = 0;
    int failures = 0;
    String? error;
    DateTime? endedAt;

    while (status == CaptureStatus.capturing) {
      try {
        final DateTime now = _clock();
        if (_forceDtcRead || _lastDtcAt == null || now.difference(_lastDtcAt!) >= dtcEvery) {
          _forceDtcRead = false;
          await _readDtcsSafely(reader, now);
        }

        final ObdValues values = await reader.readCycle(cycle++);
        final DateTime readAt = _clock();
        final Reading reading = Reading(seq: _seq++, time: readAt, values: values);
        await store.addReading(sessionId!, reading);
        latest = values;
        _lastReadingAt = readAt;
        _sinceLastReading
          ..reset()
          ..start();
        readingsCaptured++;
        failures = 0;
        final int ms = _clockWatch.elapsedMilliseconds;
        if (ms > 0) readingsPerSecond = readingsCaptured * 1000 / ms;
        notifyListeners();
      } on ObdException catch (e) {
        failures++;
        lastLinkError = e.message;
        // Bluetooth caído = reconecta já. Outras falhas (adaptador mudo, ignição desligada) só depois
        // de algumas seguidas, para não reagir a um tropeço isolado.
        if (failures >= maxConsecutiveFailures || e is ObdConnectionException) {
          final ObdReader? fresh = await _reconnect();
          if (fresh != null) {
            reader = fresh;
            failures = 0;
          } else if (_reconnectFailure != null) {
            error = _reconnectFailure;
            endedAt = _lastReadingAt; // a sessão termina quando chegou a última leitura, não depois
            break;
          }
        }
      } catch (e) {
        error = 'Erro inesperado na captura: ${describeError(e)}';
        break;
      }

      _maybeSync();
      await Future<void>.delayed(Duration.zero); // cede a vez para a tela e para o envio
    }

    await _finalize(error, endedAt: endedAt);
  }

  void _maybeSync() {
    final DateTime? last = lastSyncAt;
    if (!_syncing && (last == null || _clock().difference(last) >= syncEvery)) {
      unawaited(_sync());
    }
  }

  /// Recupera a conexão com o adaptador sem encerrar a sessão: fecha o que sobrou da conexão
  /// antiga e tenta abrir outra, com esperas crescentes entre as tentativas. Devolve o novo leitor,
  /// ou `null` se o usuário parou a captura ou se passou tempo demais sem nenhuma leitura
  /// (nesse caso [_reconnectFailure] explica).
  Future<ObdReader?> _reconnect() async {
    _reconnectFailure = null;
    final ObdLink? old = _link;
    _link = null;
    if (old != null) await _closeQuietly(old);

    reconnecting = true;
    reconnectAttempts = 0;
    notifyListeners();

    Duration wait = reconnectBackoff;
    while (status == CaptureStatus.capturing) {
      if (_sinceLastReading.elapsed >= reconnectGiveUpAfter) {
        _reconnectFailure = 'Conexão com o adaptador perdida: sem leituras há '
            '${_describe(reconnectGiveUpAfter)} e a reconexão não funcionou.';
        break;
      }
      await _waitWhileCapturing(wait);
      if (status != CaptureStatus.capturing) break;

      reconnectAttempts++;
      notifyListeners();
      final ObdLink? link = await _tryConnect();
      if (link == null) {
        wait = wait * 2 > reconnectMaxBackoff ? reconnectMaxBackoff : wait * 2;
        continue;
      }
      if (status != CaptureStatus.capturing) {
        await _closeQuietly(link);
        break;
      }

      _link = link;
      reconnecting = false;
      reconnections++;
      lastReconnectAt = _clock();
      lastLinkError = null;
      notifyListeners();
      return link.reader;
    }

    reconnecting = false;
    notifyListeners();
    return null;
  }

  /// Uma tentativa de conexão. Se ela travar além do limite, ou se o usuário parar a captura,
  /// é abandonada; e se terminar depois disso, a conexão que abriu é fechada para não ficar vazando.
  Future<ObdLink?> _tryConnect() async {
    final Completer<ObdLink?> result = Completer<ObdLink?>();

    unawaited(
      linkFactory(_deviceAddress!).then<void>((ObdLink link) {
        if (result.isCompleted) {
          unawaited(_closeQuietly(link)); // chegou tarde demais
        } else {
          result.complete(link);
        }
      }, onError: (Object e) {
        lastLinkError = describeError(e);
        if (!result.isCompleted) result.complete(null);
      }),
    );

    final Timer timer = Timer(reconnectAttemptTimeout, () {
      if (!result.isCompleted) {
        lastLinkError = 'A tentativa de conexão demorou demais';
        result.complete(null);
      }
    });
    unawaited(_stopSignal.future.then<void>((_) {
      if (!result.isCompleted) result.complete(null);
    }));

    final ObdLink? link = await result.future;
    timer.cancel();
    return link;
  }

  /// Espera sem travar a parada: acorda em passos curtos e já aproveita para enviar a fila.
  Future<void> _waitWhileCapturing(Duration total) async {
    const Duration step = Duration(milliseconds: 100);
    final Stopwatch watch = Stopwatch()..start();
    while (status == CaptureStatus.capturing && watch.elapsed < total) {
      final Duration left = total - watch.elapsed;
      await Future<void>.delayed(left < step ? left : step);
      _maybeSync();
    }
  }

  Future<void> _closeQuietly(ObdLink link) async {
    try {
      // Numa conexão morta o fechamento pode ficar pendurado; não deixa isso travar a reconexão.
      await link.close().timeout(const Duration(seconds: 3));
    } catch (_) {
      // já estava desconectado
    }
  }

  String _describe(Duration d) => d >= const Duration(minutes: 1) ? '${d.inMinutes} min' : '${d.inSeconds} s';

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

  Future<void> _finalize(String? error, {DateTime? endedAt}) async {
    final ObdLink? link = _link;
    _link = null;
    final String? id = sessionId;
    if (id != null) await store.endSession(id, endedAt ?? _clock());

    while (_syncing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _sync();

    if (link != null) await _closeQuietly(link);
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
