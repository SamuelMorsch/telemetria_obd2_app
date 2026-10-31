import '../core/models.dart';
import '../core/sync/outbox.dart';

/// O que o controle da captura precisa gravar no celular enquanto dirige.
abstract class CaptureStore {
  Future<void> createSession(PendingSession session);

  Future<void> addReading(String sessionId, Reading reading);

  Future<void> addDtc(String sessionId, Dtc dtc, DateTime detectedAt);

  Future<void> endSession(String sessionId, DateTime endedAt);
}
