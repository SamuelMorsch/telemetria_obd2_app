import '../models.dart';
import 'outbox.dart';

/// Por que uma rodada de envio parou antes de terminar.
enum SyncStop { unauthorized, unavailable }

class SyncResult {
  const SyncResult({
    required this.readingsSent,
    required this.dtcsSent,
    required this.discarded,
    this.stoppedBy,
  });

  final int readingsSent;
  final int dtcsSent;

  /// Itens que o servidor recusou e foram descartados (para não travar a fila).
  final int discarded;

  /// Nulo = enviou tudo que havia.
  final SyncStop? stoppedBy;

  bool get completed => stoppedBy == null;
}

/// Envia o que está na fila local ao servidor, em lotes, sem perder nem duplicar dados.
///
/// Regras:
/// - Só apaga do celular o que o servidor confirmou.
/// - Falha de rede/servidor (5xx, 429): pára e mantém tudo para a próxima rodada.
/// - Login expirado (401): pára; é preciso entrar de novo.
/// - Lote recusado (4xx): reenvia item a item e descarta só o que o servidor recusar.
/// - O encerramento da sessão só é enviado depois de todos os dados dela.
class OutboxSyncer {
  OutboxSyncer({
    required this.store,
    required this.api,
    this.readingBatchSize = 200,
    this.dtcBatchSize = 50,
  });

  final OutboxStore store;
  final TelemetryApi api;
  final int readingBatchSize;
  final int dtcBatchSize;

  Future<SyncResult> syncOnce() async {
    int readingsSent = 0;
    int dtcsSent = 0;
    int discarded = 0;

    SyncResult result(SyncStop? stop) => SyncResult(
          readingsSent: readingsSent,
          dtcsSent: dtcsSent,
          discarded: discarded,
          stoppedBy: stop,
        );

    try {
      for (final PendingSession session in await store.sessionsToSync()) {
        if (!session.opened) {
          try {
            await api.openSession(session);
          } on ApiRejectedException catch (e) {
            await store.markSessionFailed(session.id, 'Servidor recusou a sessão (HTTP ${e.status})');
            continue;
          }
          await store.markSessionOpened(session.id);
        }

        while (true) {
          final List<Reading> batch = await store.pendingReadings(session.id, readingBatchSize);
          if (batch.isEmpty) break;
          final int dropped = await _sendReadings(session.id, batch);
          discarded += dropped;
          readingsSent += batch.length - dropped;
        }

        while (true) {
          final List<PendingDtc> batch = await store.pendingDtcs(session.id, dtcBatchSize);
          if (batch.isEmpty) break;
          final int dropped = await _sendDtcs(session.id, batch);
          discarded += dropped;
          dtcsSent += batch.length - dropped;
        }

        final DateTime? endedAt = session.endedAt;
        if (endedAt != null && !session.endSent) {
          try {
            await api.endSession(session.id, endedAt);
          } on ApiRejectedException {
            // Encerramento recusado: não vale insistir. Os dados já foram enviados.
          }
          await store.markEndSent(session.id);
        }
      }
    } on ApiUnauthorizedException {
      return result(SyncStop.unauthorized);
    } on ApiUnavailableException {
      return result(SyncStop.unavailable);
    }
    return result(null);
  }

  /// Devolve quantas leituras foram descartadas (recusadas pelo servidor).
  Future<int> _sendReadings(String sessionId, List<Reading> batch) async {
    try {
      await api.sendReadings(sessionId, batch);
      await store.deleteReadings(sessionId, <int>[for (final Reading r in batch) r.seq]);
      return 0;
    } on ApiRejectedException {
      // Algum item do lote é inválido: isola reenviando um a um.
      int dropped = 0;
      for (final Reading r in batch) {
        try {
          await api.sendReadings(sessionId, <Reading>[r]);
        } on ApiRejectedException {
          dropped++;
        }
        await store.deleteReadings(sessionId, <int>[r.seq]);
      }
      return dropped;
    }
  }

  Future<int> _sendDtcs(String sessionId, List<PendingDtc> batch) async {
    try {
      await api.sendDtcs(sessionId, batch);
      await store.deleteDtcs(sessionId, <int>[for (final PendingDtc d in batch) d.id]);
      return 0;
    } on ApiRejectedException {
      int dropped = 0;
      for (final PendingDtc d in batch) {
        try {
          await api.sendDtcs(sessionId, <PendingDtc>[d]);
        } on ApiRejectedException {
          dropped++;
        }
        await store.deleteDtcs(sessionId, <int>[d.id]);
      }
      return dropped;
    }
  }
}
