import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/core/models.dart';

void main() {
  test('Reading.toApiJson usa horário UTC e omite campos ausentes', () {
    final Reading reading = Reading(
      seq: 7,
      time: DateTime.utc(2026, 10, 14, 12, 0, 5),
      values: const ObdValues(batteryVoltage: 14.2, rpm: 2500),
    );

    expect(reading.toApiJson(), <String, Object?>{
      'seq': 7,
      'time': '2026-10-14T12:00:05.000Z',
      'battery_voltage': 14.2,
      'rpm': 2500,
    });
  });

  test('horário local é convertido para UTC', () {
    final Reading reading = Reading(
      seq: 0,
      time: DateTime.parse('2026-10-14T09:00:00-03:00'),
      values: const ObdValues(rpm: 800),
    );

    expect(reading.toApiJson()['time'], '2026-10-14T12:00:00.000Z');
  });

  test('ObdValues.isEmpty', () {
    expect(const ObdValues().isEmpty, isTrue);
    expect(const ObdValues(rpm: 0).isEmpty, isFalse);
  });

  test('Dtc compara por código e estado', () {
    expect(const Dtc(code: 'P0562', status: DtcStatus.stored), const Dtc(code: 'P0562', status: DtcStatus.stored));
    expect(const Dtc(code: 'P0562', status: DtcStatus.stored) == const Dtc(code: 'P0562', status: DtcStatus.pending), isFalse);
    expect(DtcStatus.pending.apiName, 'pending');
  });
}
