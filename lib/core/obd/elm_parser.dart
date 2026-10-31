/// Decodificação das respostas do adaptador ELM327. Funções puras, sem I/O.

const List<String> _fatalErrors = <String>[
  'UNABLE TO CONNECT',
  'CAN ERROR',
  'BUS BUSY',
  'BUS ERROR',
  'FB ERROR',
  'DATA ERROR',
  'BUFFER FULL',
  'STOPPED',
];

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _hexOnly = RegExp(r'^[0-9A-F]+$');

String _compact(String line) => line.replaceAll(_whitespace, '').toUpperCase();

/// Divide a resposta em linhas, removendo o eco do comando, o prompt ">", linhas vazias
/// e os avisos de busca de protocolo.
List<String> cleanLines(String raw, {String? command}) {
  final String? echo = command == null ? null : _compact(command);
  final RegExp searching = RegExp(r'^SEARCHING\.\.\.$', caseSensitive: false);
  final RegExp busInit = RegExp(r'^BUS INIT', caseSensitive: false);
  return raw
      .replaceAll('\u0000', '')
      .split(RegExp(r'[\r\n]+'))
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty && l != '>')
      .where((String l) => echo == null || _compact(l) != echo)
      .where((String l) => !searching.hasMatch(l) && !busInit.hasMatch(l))
      .toList();
}

/// Nome do erro grave presente na resposta, ou null. "NO DATA" não é grave
/// (o veículo simplesmente não tem a informação).
String? fatalError(List<String> lines) {
  for (final String line in lines) {
    final String upper = line.toUpperCase();
    for (final String error in _fatalErrors) {
      if (upper.contains(error)) return error;
    }
    if (upper == '?') return '?';
  }
  return null;
}

bool isNoData(List<String> lines) => lines.any((String l) => l.toUpperCase().contains('NO DATA'));

/// Resposta do comando ATRV (tensão no conector). Ex.: "12.6V".
double? parseVoltage(List<String> lines) {
  final RegExp pattern = RegExp(r'^(\d{1,2}(?:\.\d+)?)\s*V?$', caseSensitive: false);
  for (final String line in lines) {
    final RegExpMatch? m = pattern.firstMatch(line);
    if (m != null) {
      final double v = double.parse(m.group(1)!);
      if (v >= 0 && v <= 40) return v;
    }
  }
  return null;
}

/// Bytes de dados de uma resposta de PID. `header` é o eco do serviço e do PID, ex.: "410C".
List<int>? pidData(List<String> lines, String header, int count) {
  for (final String line in lines) {
    final String s = _compact(line);
    if (!s.startsWith(header)) continue;
    final String hex = s.substring(header.length);
    if (hex.length >= count * 2 && _hexOnly.hasMatch(hex)) {
      return <int>[
        for (int i = 0; i < count; i++) int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
      ];
    }
  }
  return null;
}

int? parseRpm(List<String> lines) {
  final List<int>? d = pidData(lines, '410C', 2);
  return d == null ? null : ((d[0] * 256 + d[1]) / 4).round();
}

int? parseSpeed(List<String> lines) {
  final List<int>? d = pidData(lines, '410D', 1);
  return d?[0];
}

int? parseCoolantTemp(List<String> lines) {
  final List<int>? d = pidData(lines, '4105', 1);
  return d == null ? null : d[0] - 40;
}

/// Tensão informada pela central do veículo (PID 01 42), em volts.
double? parseEcuVoltage(List<String> lines) {
  final List<int>? d = pidData(lines, '4142', 2);
  return d == null ? null : (d[0] * 256 + d[1]) / 1000;
}

String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');

/// Mapa de PIDs suportados de uma faixa (0100, 0120, 0140...): 4 bytes.
List<int>? parseSupportedMask(List<String> lines, int base) {
  final String header = '41${_hex2(base)}';
  return pidData(lines, header, 4);
}

/// O PID `pid` consta no mapa da faixa que começa em `base`? (PID base+1 é o bit mais alto.)
bool maskSupports(List<int> mask, int base, int pid) {
  final int index = pid - base - 1;
  if (index < 0 || index > 31) return false;
  return ((mask[index ~/ 8] >> (7 - (index % 8))) & 1) == 1;
}

/// Resposta do comando ATDPN: número do protocolo (6 a 9 = CAN).
int? parseProtocol(List<String> lines) {
  final RegExp pattern = RegExp(r'^A?([0-9A-C])$', caseSensitive: false);
  for (final String line in lines) {
    final RegExpMatch? m = pattern.firstMatch(line.trim());
    if (m != null) return int.parse(m.group(1)!, radix: 16);
  }
  return null;
}

bool isCanProtocol(int? protocol) => protocol != null && protocol >= 6 && protocol <= 9;

const List<String> _dtcLetters = <String>['P', 'C', 'B', 'U'];

String? _decodeDtc(int b1, int b2) {
  if (b1 == 0 && b2 == 0) return null; // enchimento
  final String letter = _dtcLetters[(b1 >> 6) & 3];
  final String second = ((b1 >> 4) & 3).toString();
  final String third = (b1 & 15).toRadixString(16).toUpperCase();
  return '$letter$second$third${_hex2(b2)}';
}

/// Decodifica a resposta aos serviços 03 (confirmados), 07 (pendentes) ou 0A (permanentes).
///
/// - Em CAN (protocolos 6 a 9) o primeiro byte depois do serviço é a QUANTIDADE de códigos.
///   Nos protocolos antigos não há esse byte, e os códigos vêm em pares, com 0000 de enchimento.
/// - Respostas longas chegam em várias partes ("0:", "1:"...), precedidas de uma linha com o
///   total de bytes. Várias centrais podem responder: cada uma é uma mensagem.
List<String> parseDtcResponse(List<String> lines, {required int mode, required bool isCan}) {
  final String header = _hex2(0x40 + mode);
  final RegExp lengthLine = RegExp(r'^[0-9A-F]{3}$');
  final RegExp frame = RegExp(r'^([0-9A-F]):([0-9A-F]*)$');

  final List<StringBuffer> messages = <StringBuffer>[];
  StringBuffer? current;
  for (int i = 0; i < lines.length; i++) {
    final String s = _compact(lines[i]);
    if (lengthLine.hasMatch(s) && i + 1 < lines.length && _compact(lines[i + 1]).startsWith('0:')) {
      continue; // total de bytes da mensagem em várias partes
    }
    final RegExpMatch? m = frame.firstMatch(s);
    if (m != null) {
      if (m.group(1) == '0') {
        current = StringBuffer(m.group(2)!);
        messages.add(current);
      } else {
        current?.write(m.group(2)!);
      }
      continue;
    }
    if (_hexOnly.hasMatch(s)) {
      current = StringBuffer(s);
      messages.add(current);
    }
  }

  final List<String> codes = <String>[];
  for (final StringBuffer buffer in messages) {
    final String text = buffer.toString();
    if (!text.startsWith(header)) continue; // resposta de outro serviço
    final List<int> bytes = <int>[];
    for (int i = header.length; i + 1 < text.length; i += 2) {
      bytes.add(int.parse(text.substring(i, i + 2), radix: 16));
    }

    List<int> body = bytes;
    if (isCan) {
      if (bytes.isEmpty) continue;
      final int announced = bytes[0] * 2;
      final int available = bytes.length - 1;
      body = bytes.sublist(1, 1 + (announced < available ? announced : available));
    }

    for (int i = 0; i + 1 < body.length; i += 2) {
      final String? code = _decodeDtc(body[i], body[i + 1]);
      if (code != null && !codes.contains(code)) codes.add(code);
    }
  }
  return codes;
}
