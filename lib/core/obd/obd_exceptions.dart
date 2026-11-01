/// Erro de comunicação com o adaptador ou com o veículo.
class ObdException implements Exception {
  ObdException(this.message);

  final String message;

  @override
  String toString() => 'ObdException: $message';
}

/// O adaptador não respondeu a tempo.
class ElmTimeoutException extends ObdException {
  ElmTimeoutException(this.command) : super('Sem resposta do adaptador ao comando $command');

  final String command;
}

/// O adaptador respondeu com um erro (UNABLE TO CONNECT, BUS BUSY, "?" etc.).
class ElmErrorException extends ObdException {
  ElmErrorException(this.command, this.error)
      : super('O adaptador respondeu "$error" ao comando $command');

  final String command;
  final String error;
}

/// Não foi possível falar com o veículo (ignição desligada, protocolo não reconhecido).
class ObdConnectionException extends ObdException {
  ObdConnectionException(super.message);
}
