import '../models.dart';
import 'elm_client.dart';
import 'elm_parser.dart';
import 'obd_exceptions.dart';

/// O que o veículo informou que suporta.
class ObdCapabilities {
  const ObdCapabilities({this.protocol, this.supportedPids = const <int>{}});

  final int? protocol;
  final Set<int> supportedPids;

  bool get isCan => isCanProtocol(protocol);

  bool supports(int pid) => supportedPids.contains(pid);
}

/// Conversa com o veículo através do [ElmClient]: inicializa o adaptador, descobre os
/// parâmetros suportados, lê os valores de cada ciclo e os códigos de falha.
class ObdReader {
  ObdReader(this._elm, {this.settleAfterReset = const Duration(milliseconds: 300)});

  final ElmClient _elm;

  /// Pausa depois do reset (ATZ): alguns adaptadores genéricos precisam dela.
  final Duration settleAfterReset;

  ObdCapabilities _capabilities = const ObdCapabilities();
  int? _lastCoolant;

  ObdCapabilities get capabilities => _capabilities;

  /// Reinicia o adaptador, escolhe o protocolo automaticamente e descobre os PIDs suportados.
  /// Lança [ObdConnectionException] se não conseguir falar com o veículo.
  Future<ObdCapabilities> initialize() async {
    await _elm.send('ATZ', timeout: const Duration(seconds: 5));
    if (settleAfterReset > Duration.zero) {
      await Future<void>.delayed(settleAfterReset);
    }
    for (final String command in const <String>['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0']) {
      await _elm.send(command);
    }

    final Set<int> supported = <int>{};
    int base = 0x00;
    while (base <= 0x40) {
      final String command = '01${_hex2(base)}';
      List<String> lines;
      try {
        lines = await _elm.send(
          command,
          timeout: base == 0 ? const Duration(seconds: 15) : const Duration(seconds: 4),
        );
      } on ElmErrorException catch (e) {
        if (base == 0) {
          throw ObdConnectionException(
            'Não foi possível falar com o veículo (${e.error}). A ignição está ligada?',
          );
        }
        break;
      }

      final List<int>? mask = parseSupportedMask(lines, base);
      if (mask == null) {
        if (base == 0) {
          throw ObdConnectionException(
            'O veículo não respondeu à consulta de parâmetros. A ignição está ligada?',
          );
        }
        break;
      }
      for (int pid = base + 1; pid <= base + 0x20; pid++) {
        if (maskSupports(mask, base, pid)) supported.add(pid);
      }
      if (!maskSupports(mask, base, base + 0x20)) break; // não há faixa seguinte
      base += 0x20;
    }

    final int? protocol = parseProtocol(await _elm.send('ATDPN'));
    _capabilities = ObdCapabilities(protocol: protocol, supportedPids: supported);
    return _capabilities;
  }

  /// Lê os valores de um ciclo. `cycle` é o número do ciclo (a temperatura, que varia devagar,
  /// só é consultada a cada 10 ciclos; nos demais repete o último valor).
  Future<ObdValues> readCycle(int cycle) async {
    double? battery;
    try {
      battery = parseVoltage(await _elm.send('ATRV'));
    } on ElmErrorException {
      battery = null; // adaptador que não suporta ATRV
    }

    int? rpm;
    int? speed;
    double? ecuVoltage;
    if (_capabilities.supports(0x0C)) rpm = parseRpm(await _elm.send('010C'));
    if (_capabilities.supports(0x0D)) speed = parseSpeed(await _elm.send('010D'));
    if (_capabilities.supports(0x42)) ecuVoltage = parseEcuVoltage(await _elm.send('0142'));
    if (_capabilities.supports(0x05) && cycle % 10 == 0) {
      _lastCoolant = parseCoolantTemp(await _elm.send('0105')) ?? _lastCoolant;
    }

    return ObdValues(
      batteryVoltage: battery,
      controlModuleVoltage: ecuVoltage,
      rpm: rpm,
      speedKmh: speed,
      coolantTempC: _lastCoolant,
    );
  }

  /// Códigos de falha: confirmados (modo 03) e pendentes (modo 07).
  Future<List<Dtc>> readDtcs() async {
    final bool can = _capabilities.isCan;
    final List<Dtc> result = <Dtc>[];

    final List<String> stored = await _elm.send('03', timeout: const Duration(seconds: 8));
    for (final String code in parseDtcResponse(stored, mode: 3, isCan: can)) {
      result.add(Dtc(code: code, status: DtcStatus.stored));
    }

    try {
      final List<String> pending = await _elm.send('07', timeout: const Duration(seconds: 8));
      for (final String code in parseDtcResponse(pending, mode: 7, isCan: can)) {
        result.add(Dtc(code: code, status: DtcStatus.pending));
      }
    } on ElmErrorException {
      // Alguns veículos não suportam o modo 07: seguimos só com os confirmados.
    }
    return result;
  }

  /// Apaga os códigos de falha e desliga a luz de aviso (serviço 04). APAGA TAMBÉM A PISTA
  /// de que o mecânico precisa: só deve ser chamado de uma tela protegida (modo oficina).
  Future<void> clearDtcs() async {
    await _elm.send('04', timeout: const Duration(seconds: 8));
  }

  String _hex2(int v) => v.toRadixString(16).toUpperCase().padLeft(2, '0');
}
