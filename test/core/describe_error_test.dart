import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/obd/obd_exceptions.dart';

void main() {
  // Textos reais que o Android devolveu nos testes em carro (com a pilha Java).
  const String adaptadorFora = 'PlatformException(connect_error, read failed, socket might closed or timeout, '
      'read ret: -1, java.io.IOException: read failed, socket might closed or timeout, read ret: -1\n'
      ' at android.bluetooth.BluetoothSocket.readAll(BluetoothSocket.java:776)\n'
      ' at android.bluetooth.BluetoothSocket.connect(BluetoothSocket.java:415)\n'
      ' at java.lang.Thread.run(Thread.java:1571)\n, null)';
  const String bluetoothDesligado = 'PlatformException(connect_error, null, java.io.IOException\n'
      ' at android.bluetooth.BluetoothDevice.createRfcommSocketToServiceRecord(BluetoothDevice.java:2306)\n'
      ' at java.lang.Thread.run(Thread.java:1571)\n, null)';

  test('adaptador fora de alcance: uma frase curta, sem a pilha Java', () {
    final String texto = describeError(Exception(adaptadorFora));

    expect(texto, contains('o adaptador não respondeu'));
    expect(texto, isNot(contains('android.bluetooth')));
    expect(texto.contains('\n'), isFalse);
  });

  test('Bluetooth do celular desligado: explica o motivo provável', () {
    final String texto = describeError(Exception(bluetoothDesligado));

    expect(texto, 'o Bluetooth do celular está desligado ou indisponível');
  });

  test('erros do próprio app mantêm a mensagem original', () {
    expect(describeError(ObdConnectionException('A conexão Bluetooth foi encerrada')), 'A conexão Bluetooth foi encerrada');
    expect(describeError(ElmTimeoutException('010C')), contains('010C'));
  });

  test('erro desconhecido: só a primeira linha, com tamanho limitado', () {
    final String longo = 'x' * 300;

    final String texto = describeError(Exception('$longo\nsegunda linha\nterceira linha'));

    expect(texto.contains('\n'), isFalse);
    expect(texto.length, lessThanOrEqualTo(101));
    expect(texto, endsWith('…'));
  });
}
