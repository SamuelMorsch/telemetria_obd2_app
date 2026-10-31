import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/obd/elm_client.dart';
import 'package:telemetria_obd2_app/core/obd/obd_exceptions.dart';
import 'package:telemetria_obd2_app/core/obd/obd_reader.dart';

import '../support/scripted_transport.dart';

ObdReader readerFor(Map<String, String> script, [ScriptedTransport? holder]) {
  final ScriptedTransport transport = holder ?? ScriptedTransport(script);
  return ObdReader(ElmClient(transport), settleAfterReset: Duration.zero);
}

void main() {
  group('inicialização', () {
    test('configura o adaptador, descobre o protocolo e os PIDs suportados', () async {
      final ScriptedTransport transport = ScriptedTransport(fakeCarScript());
      final ObdReader reader = ObdReader(ElmClient(transport), settleAfterReset: Duration.zero);

      final ObdCapabilities caps = await reader.initialize();

      expect(caps.protocol, 6);
      expect(caps.isCan, isTrue);
      expect(caps.supports(0x0C), isTrue); // rotação
      expect(caps.supports(0x0D), isTrue); // velocidade
      expect(caps.supports(0x05), isTrue); // temperatura
      expect(caps.supports(0x42), isTrue); // tensão da central
      expect(caps.supports(0x02), isFalse);
      expect(
        transport.sent,
        <String>['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0', '0100', '0120', '0140', 'ATDPN'],
      );
    });

    test('carro sem a faixa 0x40: não consulta 0140 e não suporta a tensão da central', () async {
      final Map<String, String> script = fakeCarScript();
      script['0100'] = '41 00 BE 3F A8 12\r\r>'; // último bit 0: não há faixa seguinte
      final ScriptedTransport transport = ScriptedTransport(script);
      final ObdReader reader = ObdReader(ElmClient(transport), settleAfterReset: Duration.zero);

      final ObdCapabilities caps = await reader.initialize();

      expect(caps.supports(0x42), isFalse);
      expect(transport.sent.contains('0120'), isFalse);
    });

    test('ignição desligada: ObdConnectionException com mensagem clara', () async {
      final Map<String, String> script = fakeCarScript();
      script['0100'] = 'UNABLE TO CONNECT\r\r>';
      final ObdReader reader = readerFor(script);

      await expectLater(
        reader.initialize(),
        throwsA(isA<ObdConnectionException>().having((ObdConnectionException e) => e.message, 'message', contains('ignição'))),
      );
    });

    test('veículo que responde NO DATA ao 0100 também é tratado como sem conexão', () async {
      final Map<String, String> script = fakeCarScript();
      script['0100'] = 'NO DATA\r\r>';
      await expectLater(readerFor(script).initialize(), throwsA(isA<ObdConnectionException>()));
    });
  });

  group('leitura de um ciclo', () {
    test('devolve tensão do adaptador, da central, rotação, velocidade e temperatura', () async {
      final ObdReader reader = readerFor(fakeCarScript());
      await reader.initialize();

      final ObdValues v = await reader.readCycle(0);

      expect(v.batteryVoltage, 14.2);
      expect(v.controlModuleVoltage, closeTo(14.428, 0.0001));
      expect(v.rpm, 1726);
      expect(v.speedKmh, 60);
      expect(v.coolantTempC, 83);
    });

    test('a temperatura só é consultada a cada 10 ciclos, mas o valor se repete nos demais', () async {
      final ScriptedTransport transport = ScriptedTransport(fakeCarScript());
      final ObdReader reader = ObdReader(ElmClient(transport), settleAfterReset: Duration.zero);
      await reader.initialize();
      transport.sent.clear();

      final ObdValues first = await reader.readCycle(0);
      final ObdValues second = await reader.readCycle(1);

      expect(first.coolantTempC, 83);
      expect(second.coolantTempC, 83);
      expect(transport.sent.where((String c) => c == '0105').length, 1);
    });

    test('adaptador sem ATRV ("?") não derruba o ciclo', () async {
      final Map<String, String> script = fakeCarScript();
      script['ATRV'] = '?\r\r>';
      final ObdReader reader = readerFor(script);
      await reader.initialize();

      final ObdValues v = await reader.readCycle(1);

      expect(v.batteryVoltage, isNull);
      expect(v.rpm, 1726);
    });
  });

  group('códigos de falha', () {
    test('lê o P0043 do carro de teste como confirmado', () async {
      final ObdReader reader = readerFor(fakeCarScript(stored: '43 01 00 43 00 00 00'));
      await reader.initialize();

      expect(await reader.readDtcs(), <Dtc>[const Dtc(code: 'P0043', status: DtcStatus.stored)]);
    });

    test('lê confirmados e pendentes', () async {
      final ObdReader reader = readerFor(
        fakeCarScript(stored: '43 01 00 43 00 00 00', pending: '47 01 05 62 00 00 00'),
      );
      await reader.initialize();

      expect(
        await reader.readDtcs(),
        <Dtc>[
          const Dtc(code: 'P0043', status: DtcStatus.stored),
          const Dtc(code: 'P0562', status: DtcStatus.pending),
        ],
      );
    });

    test('carro sem falhas devolve lista vazia', () async {
      final ObdReader reader = readerFor(fakeCarScript());
      await reader.initialize();
      expect(await reader.readDtcs(), isEmpty);
    });

    test('carro que não suporta o modo 07 segue só com os confirmados', () async {
      final ObdReader reader = readerFor(fakeCarScript(stored: '43 01 00 43 00 00 00', pending: '?'));
      await reader.initialize();

      expect(await reader.readDtcs(), <Dtc>[const Dtc(code: 'P0043', status: DtcStatus.stored)]);
    });

    test('apagar códigos envia o serviço 04', () async {
      final ScriptedTransport transport = ScriptedTransport(fakeCarScript());
      final ObdReader reader = ObdReader(ElmClient(transport), settleAfterReset: Duration.zero);
      await reader.initialize();

      await reader.clearDtcs();

      expect(transport.sent.last, '04');
    });
  });
}
