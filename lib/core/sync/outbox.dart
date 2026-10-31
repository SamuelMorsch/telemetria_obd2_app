import '../models.dart';

/// Sessão local ainda com algo a enviar ao servidor.
class PendingSession {
  const PendingSession({
    required this.id,
    required this.vehicleId,
    required this.startedAt,
    required this.source,
    this.appVersion,
    this.endedAt,
    this.opened = false,
    this.endSent = false,
  });

  final String id;
  final String vehicleId;
  final DateTime startedAt;

  /// 'obd' (adaptador real) ou 'simulator' (modo demonstração).
  final String source;
  final String? appVersion;

  /// Preenchido quando a captura terminou no celular. Nulo = ainda capturando.
  final DateTime? endedAt;

  /// Já foi aberta no servidor (POST /api/sessions)?
  final bool opened;

  /// O encerramento já foi comunicado ao servidor?
  final bool endSent;
}

/// Código de falha guardado localmente, à espera de envio.
class PendingDtc {
  const PendingDtc({required this.id, required this.dtc, required this.detectedAt});

  /// Identificador local (para apagar depois de enviado).
  final int id;
  final Dtc dtc;
  final DateTime detectedAt;
}

/// Armazenamento local (SQLite no celular). Tudo que a captura produz entra aqui primeiro;
/// só sai depois que o servidor confirmou o recebimento.
abstract class OutboxStore {
  /// Sessões com algo a enviar (dados, abertura ou encerramento), da mais antiga para a mais nova.
  /// Não inclui as que foram marcadas como falhas.
  Future<List<PendingSession>> sessionsToSync();

  Future<void> markSessionOpened(String sessionId);

  /// Leituras ainda não enviadas, em ordem de `seq`.
  Future<List<Reading>> pendingReadings(String sessionId, int limit);

  Future<void> deleteReadings(String sessionId, List<int> seqs);

  Future<List<PendingDtc>> pendingDtcs(String sessionId, int limit);

  Future<void> deleteDtcs(String sessionId, List<int> ids);

  Future<void> markEndSent(String sessionId);

  /// O servidor recusou a sessão de forma definitiva: pára de tentar, mas mantém o registro.
  Future<void> markSessionFailed(String sessionId, String reason);
}

/// Cliente da API de telemetria. Todas as chamadas são idempotentes no servidor.
abstract class TelemetryApi {
  Future<void> openSession(PendingSession session);

  Future<void> sendReadings(String sessionId, List<Reading> readings);

  Future<void> sendDtcs(String sessionId, List<PendingDtc> dtcs);

  Future<void> endSession(String sessionId, DateTime endedAt);
}

/// 401: o login expirou. Nada será enviado até o usuário entrar de novo.
class ApiUnauthorizedException implements Exception {
  const ApiUnauthorizedException();
}

/// 4xx (exceto 401 e 429): o servidor recusou ESTES dados. Insistir não adianta.
class ApiRejectedException implements Exception {
  const ApiRejectedException(this.status);

  final int status;
}

/// Sem rede, 5xx ou 429: tente de novo mais tarde, sem apagar nada.
class ApiUnavailableException implements Exception {
  const ApiUnavailableException();
}
