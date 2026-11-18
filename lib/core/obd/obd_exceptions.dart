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

/// Resume em uma frase curta o motivo de uma falha de conexão para mostrar na tela.
///
/// As exceções do Bluetooth do Android trazem a pilha Java inteira (dezenas de linhas), o que não
/// ajuda quem olha a tela do celular. Os erros já tratados pelo app ([ObdException]) têm mensagem
/// própria e curta.
String describeError(Object error) {
  if (error is ObdException) return error.message;
  final String text = '$error';
  final String lower = text.toLowerCase();
  if (lower.contains('createrfcommsocket')) {
    return 'o Bluetooth do celular está desligado ou indisponível';
  }
  if (lower.contains('read failed') || lower.contains('socket might closed') || lower.contains('connect_error')) {
    return 'o adaptador não respondeu (fora de alcance, desconectado ou sem energia)';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'o adaptador demorou demais para responder';
  }
  final String firstLine = text.split('\n').first.trim();
  return firstLine.length > 100 ? '${firstLine.substring(0, 100)}…' : firstLine;
}
