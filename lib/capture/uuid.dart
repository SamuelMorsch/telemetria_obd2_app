import 'dart:math';

/// UUID versão 4 (aleatório). O app gera o id da sessão: assim, reenviar a abertura da sessão
/// depois de uma falha de rede não cria uma segunda sessão no servidor.
String generateUuidV4([Random? random]) {
  final Random r = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final String h = bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
