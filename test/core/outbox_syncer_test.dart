import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/sync/outbox.dart';
import 'package:telemetria_obd2_app/core/sync/outbox_syncer.dart';

import '../support/memory_outbox.dart';

PendingSession session({DateTime? endedAt, bool opened = false, String id = 's1', int minute = 0}) => PendingSession(
      id: id,
      vehicleId: 'v1',
      startedAt: DateTime.utc(2026, 10, 14, 12, minute),
      source: 'obd',
      endedAt: endedAt,
      opened: opened,
    );

void main() {
  late MemoryOutbox store;
  late FakeApi api;
  late OutboxSyncer syncer;

  setUp(() {
    store = MemoryOutbox();
    api = FakeApi();
    syncer = OutboxSyncer(store: store, api: api, readingBatchSize: 100);
  });

  test('abre a sessão, envia tudo em lotes e esvazia a fila', () async {
    store.addSession(session());
    store.addReadings('s1', 250);

    final SyncResult result = await syncer.syncOnce();

    expect(result.completed, isTrue);
    expect(result.readingsSent, 250);
    expect(api.opened, <String>['s1']);
    expect(api.readingBatches.map((List<int> b) => b.length), <int>[100, 100, 50]);
    expect(store.pendingReadingCount('s1'), 0);
    expect(store.sessions['s1']!.opened, isTrue);
  });

  test('envia os códigos de falha junto', () async {
    store.addSession(session());
    store.dtcs['s1']!.addAll(<PendingDtc>[
      PendingDtc(id: 1, dtc: const Dtc(code: 'P0043', status: DtcStatus.stored), detectedAt: DateTime.utc(2026, 10, 14, 12)),
      PendingDtc(id: 2, dtc: const Dtc(code: 'P0562', status: DtcStatus.pending), detectedAt: DateTime.utc(2026, 10, 14, 12)),
    ]);

    final SyncResult result = await syncer.syncOnce();

    expect(result.dtcsSent, 2);
    expect(api.dtcCodes, <String>['P0043/stored', 'P0562/pending']);
    expect(store.dtcs['s1'], isEmpty);
  });

  test('sem rede: pára, não apaga nada e na próxima rodada conclui', () async {
    store.addSession(session());
    store.addReadings('s1', 30);
    api.failWith = const ApiUnavailableException();

    final SyncResult first = await syncer.syncOnce();

    expect(first.stoppedBy, SyncStop.unavailable);
    expect(store.pendingReadingCount('s1'), 30);

    api.failWith = null;
    final SyncResult second = await syncer.syncOnce();

    expect(second.completed, isTrue);
    expect(second.readingsSent, 30);
    expect(store.pendingReadingCount('s1'), 0);
  });

  test('queda no meio do envio mantém apenas o que ainda não foi confirmado', () async {
    store.addSession(session(opened: true));
    store.addReadings('s1', 150); // lotes de 100 e 50

    // Deixa o primeiro lote passar e derruba o segundo.
    final _FlakyApi flaky = _FlakyApi(failAfterBatches: 1);
    final SyncResult result = await OutboxSyncer(store: store, api: flaky, readingBatchSize: 100).syncOnce();

    expect(result.stoppedBy, SyncStop.unavailable);
    expect(result.readingsSent, 100);
    expect(store.pendingReadingCount('s1'), 50);
    expect(store.readings['s1']!.first.seq, 100);
  });

  test('401: pára com "unauthorized" e preserva os dados', () async {
    store.addSession(session());
    store.addReadings('s1', 10);
    api.failWith = const ApiUnauthorizedException();

    final SyncResult result = await syncer.syncOnce();

    expect(result.stoppedBy, SyncStop.unauthorized);
    expect(store.pendingReadingCount('s1'), 10);
  });

  test('lote com uma leitura inválida: reenvia uma a uma e descarta só a recusada', () async {
    store.addSession(session(opened: true));
    store.addReadings('s1', 5);
    api.rejectSeqs.add(3);

    final SyncResult result = await syncer.syncOnce();

    expect(result.completed, isTrue);
    expect(result.discarded, 1);
    expect(result.readingsSent, 4);
    expect(store.pendingReadingCount('s1'), 0);
    expect(api.readingBatches.expand((List<int> b) => b).toList()..sort(), <int>[0, 1, 2, 4]);
  });

  test('código de falha recusado é descartado sem travar os demais', () async {
    store.addSession(session(opened: true));
    store.dtcs['s1']!.addAll(<PendingDtc>[
      PendingDtc(id: 1, dtc: const Dtc(code: 'P0043', status: DtcStatus.stored), detectedAt: DateTime.utc(2026, 10, 14)),
      PendingDtc(id: 2, dtc: const Dtc(code: 'P0562', status: DtcStatus.stored), detectedAt: DateTime.utc(2026, 10, 14)),
    ]);
    api.rejectDtcCodes.add('P0043');

    final SyncResult result = await syncer.syncOnce();

    expect(result.discarded, 1);
    expect(result.dtcsSent, 1);
    expect(api.dtcCodes, <String>['P0562/stored']);
    expect(store.dtcs['s1'], isEmpty);
  });

  test('sessão recusada na abertura é marcada como falha e as outras seguem', () async {
    store.addSession(session(id: 'ruim', minute: 0));
    store.addSession(session(id: 'boa', minute: 5));
    store.addReadings('ruim', 3);
    store.addReadings('boa', 3);
    api.rejectOpen = true;

    // A primeira abertura é recusada; depois a API volta ao normal para a segunda.
    final SyncResult first = await OutboxSyncer(store: store, api: _RejectFirstOpenApi(api)).syncOnce();

    expect(first.completed, isTrue);
    expect(store.failed.containsKey('ruim'), isTrue);
    expect(store.pendingReadingCount('boa'), 0);
    expect(store.pendingReadingCount('ruim'), 3); // dados mantidos no celular
  });

  test('o encerramento só é enviado depois dos dados, e só se a captura terminou', () async {
    final DateTime end = DateTime.utc(2026, 10, 14, 12, 10);
    store.addSession(session(id: 'fechada', endedAt: end, minute: 0));
    store.addSession(session(id: 'ativa', minute: 20));
    store.addReadings('fechada', 5);
    store.addReadings('ativa', 5);

    await syncer.syncOnce();

    expect(api.ended, <String>['fechada']); // a ativa continua aberta
    expect(store.sessions['fechada']!.endSent, isTrue);
    expect(store.sessions['ativa']!.endSent, isFalse);
  });

  test('sessão encerrada sem dados pendentes ainda comunica o encerramento, uma vez só', () async {
    store.addSession(session(endedAt: DateTime.utc(2026, 10, 14, 12, 5), opened: true));

    await syncer.syncOnce();
    await syncer.syncOnce();

    expect(api.ended, <String>['s1']);
  });

  test('sem nada a enviar: conclui sem chamar a API', () async {
    final SyncResult result = await syncer.syncOnce();

    expect(result.completed, isTrue);
    expect(result.readingsSent, 0);
    expect(api.opened, isEmpty);
  });
}

/// API que aceita N lotes e depois fica indisponível.
class _FlakyApi extends FakeApi {
  _FlakyApi({required this.failAfterBatches});

  final int failAfterBatches;

  @override
  Future<void> sendReadings(String sessionId, List<Reading> readings) async {
    if (readingBatches.length >= failAfterBatches) throw const ApiUnavailableException();
    await super.sendReadings(sessionId, readings);
  }
}

/// Recusa só a primeira abertura de sessão.
class _RejectFirstOpenApi implements TelemetryApi {
  _RejectFirstOpenApi(this._inner);

  final FakeApi _inner;
  bool _first = true;

  @override
  Future<void> openSession(PendingSession session) async {
    if (_first) {
      _first = false;
      throw const ApiRejectedException(404);
    }
    _inner.rejectOpen = false;
    await _inner.openSession(session);
  }

  @override
  Future<void> sendReadings(String sessionId, List<Reading> readings) => _inner.sendReadings(sessionId, readings);

  @override
  Future<void> sendDtcs(String sessionId, List<PendingDtc> dtcs) => _inner.sendDtcs(sessionId, dtcs);

  @override
  Future<void> endSession(String sessionId, DateTime endedAt) => _inner.endSession(sessionId, endedAt);
}
