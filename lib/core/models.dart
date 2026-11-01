/// Valores lidos do veículo em um ciclo de leitura. Qualquer campo pode faltar
/// (nem todo carro responde a todos os parâmetros).
class ObdValues {
  const ObdValues({
    this.batteryVoltage,
    this.controlModuleVoltage,
    this.rpm,
    this.speedKmh,
    this.coolantTempC,
  });

  /// Tensão medida no conector OBD pelo adaptador (comando ATRV), em volts.
  final double? batteryVoltage;

  /// Tensão informada pela central do veículo (PID 01 42), em volts.
  final double? controlModuleVoltage;
  final int? rpm;
  final int? speedKmh;
  final int? coolantTempC;

  bool get isEmpty =>
      batteryVoltage == null &&
      controlModuleVoltage == null &&
      rpm == null &&
      speedKmh == null &&
      coolantTempC == null;
}

/// Uma leitura com número de sequência e horário, pronta para enviar à API.
class Reading {
  const Reading({required this.seq, required this.time, required this.values});

  /// Número sequencial dentro da sessão. Com o horário, identifica a leitura:
  /// reenviar a mesma leitura não a duplica no servidor.
  final int seq;
  final DateTime time;
  final ObdValues values;

  /// Formato esperado por POST /api/sessions/:id/readings (campos ausentes são omitidos).
  Map<String, Object?> toApiJson() {
    return <String, Object?>{
      'seq': seq,
      'time': time.toUtc().toIso8601String(),
      if (values.batteryVoltage != null) 'battery_voltage': values.batteryVoltage,
      if (values.controlModuleVoltage != null) 'control_module_voltage': values.controlModuleVoltage,
      if (values.rpm != null) 'rpm': values.rpm,
      if (values.speedKmh != null) 'speed_kmh': values.speedKmh,
      if (values.coolantTempC != null) 'coolant_temp_c': values.coolantTempC,
    };
  }
}

/// Estado de um código de falha: confirmado (modo 03) ou pendente (modo 07).
enum DtcStatus { stored, pending }

extension DtcStatusApi on DtcStatus {
  String get apiName => this == DtcStatus.stored ? 'stored' : 'pending';
}

/// Código de falha (DTC), como P0043.
class Dtc {
  const Dtc({required this.code, required this.status});

  final String code;
  final DtcStatus status;

  @override
  bool operator ==(Object other) => other is Dtc && other.code == code && other.status == status;

  @override
  int get hashCode => Object.hash(code, status);

  @override
  String toString() => 'Dtc($code, ${status.apiName})';
}
