/// Canal de bytes até o adaptador ELM327. Em produção é o Bluetooth clássico (SPP);
/// nos testes, uma versão com respostas combinadas. Isola o resto do app da biblioteca de Bluetooth.
abstract class ObdTransport {
  /// Bytes que chegam do adaptador, em pedaços de qualquer tamanho.
  Stream<List<int>> get input;

  Future<void> write(List<int> bytes);

  Future<void> close();
}
