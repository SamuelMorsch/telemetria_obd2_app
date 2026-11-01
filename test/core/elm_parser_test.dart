import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/obd/elm_parser.dart';

List<String> lines(String raw, [String? command]) => cleanLines(raw, command: command);

void main() {
  group('limpeza da resposta', () {
    test('remove eco, SEARCHING, prompt e linhas vazias', () {
      expect(
        lines('0100\r\rSEARCHING...\r41 00 BE 3F A8 13 \r\r>', '0100'),
        <String>['41 00 BE 3F A8 13'],
      );
      expect(lines('ATRV\r12.6V\r\r>', 'ATRV'), <String>['12.6V']);
      expect(lines('BUS INIT: ...OK\r41 0C 1A F8\r>'), <String>['41 0C 1A F8']);
    });

    test('ignora caracteres nulos que alguns adaptadores enviam', () {
      expect(lines('12.6V\u0000\r>'), <String>['12.6V']);
    });
  });

  group('erros', () {
    test('erros graves são identificados; NO DATA não é grave', () {
      expect(fatalError(lines('UNABLE TO CONNECT\r\r>')), 'UNABLE TO CONNECT');
      expect(fatalError(lines('?\r\r>')), '?');
      expect(fatalError(lines('CAN ERROR\r>')), 'CAN ERROR');
      expect(fatalError(lines('NO DATA\r\r>')), isNull);
      expect(isNoData(lines('NO DATA\r\r>')), isTrue);
      expect(fatalError(lines('41 0C 1A F8\r>')), isNull);
    });
  });

  group('tensão do adaptador (ATRV)', () {
    test('aceita com e sem o V e com espaço', () {
      expect(parseVoltage(<String>['12.6V']), 12.6);
      expect(parseVoltage(<String>['14.4']), 14.4);
      expect(parseVoltage(<String>['12.6 V']), 12.6);
    });

    test('rejeita lixo e valores impossíveis', () {
      expect(parseVoltage(<String>['?']), isNull);
      expect(parseVoltage(<String>['ELM327 v1.5']), isNull);
      expect(parseVoltage(<String>['99.9V']), isNull);
    });
  });

  group('PIDs', () {
    test('rotação, velocidade, temperatura e tensão da central', () {
      expect(parseRpm(lines('41 0C 1A F8\r>')), 1726);
      expect(parseSpeed(lines('41 0D 3C\r>')), 60);
      expect(parseCoolantTemp(lines('41 05 7B\r>')), 83);
      expect(parseEcuVoltage(lines('41 42 38 5C\r>')), closeTo(14.428, 0.0001));
    });

    test('sem espaços (ATS0) também funciona', () {
      expect(parseRpm(lines('410C1AF8\r>')), 1726);
    });

    test('resposta ausente, curta ou de outro PID vira nulo', () {
      expect(parseRpm(lines('NO DATA\r>')), isNull);
      expect(parseRpm(lines('41 0C 1A\r>')), isNull);
      expect(parseRpm(lines('41 0D 3C\r>')), isNull);
    });
  });

  group('PIDs suportados', () {
    test('lê o mapa e consulta os bits', () {
      final List<int>? mask = parseSupportedMask(lines('41 00 BE 3F A8 13\r>'), 0x00);
      expect(mask, <int>[0xBE, 0x3F, 0xA8, 0x13]);
      expect(maskSupports(mask!, 0x00, 0x0C), isTrue);
      expect(maskSupports(mask, 0x00, 0x0D), isTrue);
      expect(maskSupports(mask, 0x00, 0x05), isTrue);
      expect(maskSupports(mask, 0x00, 0x02), isFalse);
      expect(maskSupports(mask, 0x00, 0x20), isTrue); // há outra faixa
    });

    test('faixa 0x40: o PID 0x42 (tensão da central)', () {
      final List<int> mask = parseSupportedMask(lines('41 40 7A 1C 80 00\r>'), 0x40)!;
      expect(maskSupports(mask, 0x40, 0x42), isTrue);
      expect(maskSupports(mask, 0x40, 0x41), isFalse);
    });

    test('PID fora da faixa não é suportado', () {
      expect(maskSupports(<int>[0xFF, 0xFF, 0xFF, 0xFF], 0x00, 0x21), isFalse);
    });
  });

  group('protocolo (ATDPN)', () {
    test('reconhece o número e se é CAN', () {
      expect(parseProtocol(<String>['A6']), 6);
      expect(parseProtocol(<String>['6']), 6);
      expect(parseProtocol(<String>['A3']), 3);
      expect(parseProtocol(<String>['?']), isNull);
      expect(isCanProtocol(6), isTrue);
      expect(isCanProtocol(9), isTrue);
      expect(isCanProtocol(3), isFalse);
      expect(isCanProtocol(null), isFalse);
    });
  });

  group('códigos de falha (DTC)', () {
    test('P0043, o código do carro de teste (CAN, quadro único)', () {
      expect(
        parseDtcResponse(lines('43 01 00 43 00 00 00\r\r>'), mode: 3, isCan: true),
        <String>['P0043'],
      );
    });

    test('dois códigos, nenhum, e legado sem byte de contagem', () {
      expect(parseDtcResponse(lines('43 02 01 33 02 34 00\r>'), mode: 3, isCan: true), <String>['P0133', 'P0234']);
      expect(parseDtcResponse(lines('43 00 00 00 00 00 00\r>'), mode: 3, isCan: true), isEmpty);
      expect(parseDtcResponse(lines('43 01 33 00 00 00 00\r>'), mode: 3, isCan: false), <String>['P0133']);
      expect(
        parseDtcResponse(lines('43 01 33 02 34 C1 00\r43 00 00 00 00 00 00\r>'), mode: 3, isCan: false),
        <String>['P0133', 'P0234', 'U0100'],
      );
    });

    test('mensagem longa em várias partes (linha de total e prefixos 0: e 1:)', () {
      const String raw = '00A\r0: 43 04 01 33 02 34\r1: 03 35 04 36 00 00 00\r>';
      expect(
        parseDtcResponse(lines(raw), mode: 3, isCan: true),
        <String>['P0133', 'P0234', 'P0335', 'P0436'],
      );
    });

    test('duas centrais respondendo (motor e transmissão)', () {
      expect(
        parseDtcResponse(lines('43 01 00 43 00 00 00\r43 01 07 00 00 00 00\r>'), mode: 3, isCan: true),
        <String>['P0043', 'P0700'],
      );
    });

    test('modo 07 (pendentes), letras C/B/U, NO DATA e contagem maior que o recebido', () {
      expect(parseDtcResponse(lines('47 01 05 62 00 00 00\r>'), mode: 7, isCan: true), <String>['P0562']);
      expect(
        parseDtcResponse(lines('43 03 41 23 81 23 C1 00\r>'), mode: 3, isCan: true),
        <String>['C0123', 'B0123', 'U0100'],
      );
      expect(parseDtcResponse(lines('NO DATA\r>'), mode: 7, isCan: true), isEmpty);
      expect(parseDtcResponse(lines('43 05 01 33\r>'), mode: 3, isCan: true), <String>['P0133']);
      expect(parseDtcResponse(lines('41 0C 1A F8\r>'), mode: 3, isCan: true), isEmpty);
    });

    test('código repetido por duas centrais aparece uma vez', () {
      expect(
        parseDtcResponse(lines('43 01 01 33 00 00 00\r43 01 01 33 00 00 00\r>'), mode: 3, isCan: true),
        <String>['P0133'],
      );
    });
  });
}
