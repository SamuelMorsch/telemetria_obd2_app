import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/obd/elm_client.dart';
import 'package:telemetria_obd2_app/core/obd/obd_exceptions.dart';
import 'package:telemetria_obd2_app/core/obd/obd_transport.dart';

import '../support/scripted_transport.dart';

/// Transporte cuja escrita falha, como um Bluetooth desconectado.
class _BrokenWriteTransport implements ObdTransport {
  final StreamController<List<int>> _controller = StreamController<List<int>>();

  @override
  Stream<List<int>> get input => _controller.stream;

  @override
  Future<void> write(List<int> bytes) async => throw StateError('Not connected');

  @override
  Future<void> close() async => _controller.close();
}

void main() {
  test('junta os pedaços da resposta e devolve as linhas sem eco nem prompt', () async {
    final ScriptedTransport transport = ScriptedTransport(
      <String, String>{'010C': '010C\r41 0C 1A F8\r\r>'},
      chunkSize: 3, // pedaços minúsculos, como no Bluetooth
    );
    final ElmClient client = ElmClient(transport);

    expect(await client.send('010C'), <String>['41 0C 1A F8']);
    expect(transport.sent, <String>['010C']);
    await client.close();
  });

  test('comandos em sequência não misturam as respostas', () async {
    final ElmClient client = ElmClient(
      ScriptedTransport(<String, String>{'ATRV': '12.6V\r\r>', '010D': '41 0D 3C\r\r>'}, chunkSize: 2),
    );

    expect(await client.send('ATRV'), <String>['12.6V']);
    expect(await client.send('010D'), <String>['41 0D 3C']);
    await client.close();
  });

  test('sem resposta: lança ElmTimeoutException', () async {
    final ElmClient client = ElmClient(ScriptedTransport(<String, String>{}));

    await expectLater(
      client.send('010C', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<ElmTimeoutException>()),
    );
    await client.close();
  });

  test('erro grave do adaptador vira ElmErrorException; NO DATA não', () async {
    final ElmClient client = ElmClient(
      ScriptedTransport(<String, String>{'0100': 'UNABLE TO CONNECT\r\r>', '07': 'NO DATA\r\r>'}),
    );

    await expectLater(
      client.send('0100'),
      throwsA(isA<ElmErrorException>().having((ElmErrorException e) => e.error, 'error', 'UNABLE TO CONNECT')),
    );
    expect(await client.send('07'), <String>['NO DATA']);
    await client.close();
  });

  test('conexão já encerrada: o comando falha na hora, sem esperar o tempo limite', () async {
    final ScriptedTransport transport = ScriptedTransport(<String, String>{});
    final ElmClient client = ElmClient(transport);
    await transport.close();
    await Future<void>.delayed(Duration.zero); // deixa chegar o aviso de "fim do fluxo"

    final Stopwatch watch = Stopwatch()..start();
    await expectLater(client.send('010C'), throwsA(isA<ObdConnectionException>()));
    expect(watch.elapsed, lessThan(const Duration(seconds: 1))); // o tempo limite padrão é de 3 s
  });

  test('a conexão cai enquanto espera a resposta: falha na hora com ObdConnectionException', () async {
    final ScriptedTransport transport = ScriptedTransport(<String, String>{}); // nunca responde
    final ElmClient client = ElmClient(transport);

    final Future<void> esperado = expectLater(client.send('010C'), throwsA(isA<ObdConnectionException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await transport.close();
    await esperado;
  });

  test('erro ao escrever no Bluetooth vira ObdConnectionException (e não um erro genérico)', () async {
    final ElmClient client = ElmClient(_BrokenWriteTransport());

    await expectLater(client.send('ATZ'), throwsA(isA<ObdConnectionException>()));
  });
}
