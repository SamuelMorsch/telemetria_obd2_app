import 'package:telemetria_obd2_app/capture/capture_store.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/sync/outbox.dart';

/// Fila local em memória, para testar o envio sem banco de dados.
class MemoryOutbox implements OutboxStore {
  final Map<String, PendingSession> sessions = <String, PendingSession>{};
  final Map<String, List<Reading>> readings = <String, List<Reading>>{};
  final Map<String, List<PendingDtc>> dtcs = <String, List<PendingDtc>>{};
  final Map<String, String> failed = <String, String>{};

  void addSession(PendingSession session) {
    sessions[session.id] = session;
    readings.putIfAbsent(session.id, () => <Reading>[]);
    dtcs.putIfAbsent(session.id, () => <PendingDtc>[]);
  }

  void addReadings(String sessionId, int count, {int from = 0}) {
    for (int i = from; i < from + count; i++) {
      readings[sessionId]!.add(
        Reading(
          seq: i,
          time: DateTime.utc(2026, 10, 14, 12, 0, i),
          values: ObdValues(batteryVoltage: 14.2, rpm: 2000 + i),
        ),
      );
    }
  }

  int pendingReadingCount(String sessionId) => readings[sessionId]!.length;

  @override
  Future<List<PendingSession>> sessionsToSync() async {
    final List<PendingSession> list = sessions.values.where((PendingSession s) {
      if (failed.containsKey(s.id)) return false;
      final bool hasData = readings[s.id]!.isNotEmpty || dtcs[s.id]!.isNotEmpty;
      final bool needsOpen = !s.opened;
      final bool needsEnd = s.endedAt != null && !s.endSent;
      return hasData || needsOpen || needsEnd;
    }).toList();
    list.sort((PendingSession a, PendingSession b) => a.startedAt.compareTo(b.startedAt));
    return list;
  }

  PendingSession _copy(PendingSession s, {bool? opened, bool? endSent, DateTime? endedAt}) => PendingSession(
        id: s.id,
        vehicleId: s.vehicleId,
        startedAt: s.startedAt,
        source: s.source,
        appVersion: s.appVersion,
        endedAt: endedAt ?? s.endedAt,
        opened: opened ?? s.opened,
        endSent: endSent ?? s.endSent,
      );

  @override
  Future<void> markSessionOpened(String sessionId) async {
    sessions[sessionId] = _copy(sessions[sessionId]!, opened: true);
  }

  @override
  Future<void> markEndSent(String sessionId) async {
    sessions[sessionId] = _copy(sessions[sessionId]!, endSent: true);
  }

  @override
  Future<void> markSessionFailed(String sessionId, String reason) async {
    failed[sessionId] = reason;
  }

  @override
  Future<List<Reading>> pendingReadings(String sessionId, int limit) async =>
      readings[sessionId]!.take(limit).toList();

  @override
  Future<void> deleteReadings(String sessionId, List<int> seqs) async {
    readings[sessionId]!.removeWhere((Reading r) => seqs.contains(r.seq));
  }

  @override
  Future<List<PendingDtc>> pendingDtcs(String sessionId, int limit) async =>
      dtcs[sessionId]!.take(limit).toList();

  @override
  Future<void> deleteDtcs(String sessionId, List<int> ids) async {
    dtcs[sessionId]!.removeWhere((PendingDtc d) => ids.contains(d.id));
  }
}

/// API de mentira que registra o que recebeu e pode falhar sob comando.
class FakeApi implements TelemetryApi {
  final List<String> opened = <String>[];
  final List<List<int>> readingBatches = <List<int>>[];
  final List<String> dtcCodes = <String>[];
  final List<String> ended = <String>[];

  /// Se definido, lançado em toda chamada (simula 401, rede fora etc.).
  Object? failWith;

  /// Leituras com estes `seq` são recusadas (HTTP 400).
  final Set<int> rejectSeqs = <int>{};

  /// Códigos de falha com este texto são recusados.
  final Set<String> rejectDtcCodes = <String>{};

  bool rejectOpen = false;

  void _maybeFail() {
    final Object? error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<void> openSession(PendingSession session) async {
    _maybeFail();
    if (rejectOpen) throw const ApiRejectedException(404);
    opened.add(session.id);
  }

  @override
  Future<void> sendReadings(String sessionId, List<Reading> readings) async {
    _maybeFail();
    if (readings.any((Reading r) => rejectSeqs.contains(r.seq))) throw const ApiRejectedException(400);
    readingBatches.add(<int>[for (final Reading r in readings) r.seq]);
  }

  @override
  Future<void> sendDtcs(String sessionId, List<PendingDtc> dtcs) async {
    _maybeFail();
    if (dtcs.any((PendingDtc d) => rejectDtcCodes.contains(d.dtc.code))) {
      throw const ApiRejectedException(400);
    }
    dtcCodes.addAll(<String>[for (final PendingDtc d in dtcs) '${d.dtc.code}/${d.dtc.status.apiName}']);
  }

  @override
  Future<void> endSession(String sessionId, DateTime endedAt) async {
    _maybeFail();
    ended.add(sessionId);
  }

  int get totalReadingsSent => readingBatches.fold(0, (int sum, List<int> b) => sum + b.length);
}

/// Memória que também recebe o que a captura grava.
class MemoryCapture extends MemoryOutbox implements CaptureStore {
  int _dtcId = 0;

  @override
  Future<void> createSession(PendingSession session) async => addSession(session);

  @override
  Future<void> addReading(String sessionId, Reading reading) async => readings[sessionId]!.add(reading);

  @override
  Future<void> addDtc(String sessionId, Dtc dtc, DateTime detectedAt) async {
    dtcs[sessionId]!.add(PendingDtc(id: ++_dtcId, dtc: dtc, detectedAt: detectedAt));
  }

  @override
  Future<void> endSession(String sessionId, DateTime endedAt) async {
    sessions[sessionId] = _copy(sessions[sessionId]!, endedAt: endedAt);
  }
}
