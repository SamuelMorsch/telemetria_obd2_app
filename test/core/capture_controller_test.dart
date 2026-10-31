import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/capture/capture_controller.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/obd/elm_client.dart';
import 'package:telemetria_obd2_app/core/obd/obd_reader.dart';
import 'package:telemetria_obd2_app/core/sync/outbox.dart';
import 'package:telemetria_obd2_app/core/sync/outbox_syncer.dart';

import '../support/memory_outbox.dart';
import '../support/scripted_transport.dart';

Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 5)}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) fail('condição não atendida em ${timeout.inSeconds}s');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

LinkFactory carFactory(Map<String, String> script) {
  return (String address) async {
    final ElmClient client = ElmClient(ScriptedTransport(script), defaultTimeout: const Duration(milliseconds: 60));
    final ObdReader reader = ObdReader(client, settleAfterReset: Duration.zero);
    await reader.initialize();
    return ObdLink(reader: reader, close: client.close);
  };
}

void main() {
  late MemoryCapture store;
  late FakeApi api;

  CaptureController controllerFor(Map<String, String> script, {LinkFactory? factory}) {
    return CaptureController(
      store: store,
      syncer: OutboxSyncer(store: store, api: api),
      linkFactory: factory ?? carFactory(script),
      syncEvery: const Duration(milliseconds: 20),
      dtcEvery: const Duration(milliseconds: 80),
      idGenerator: () => 'sessao-teste',
    );
  }

  setUp(() {
    store = MemoryCapture();
    api = FakeApi();
  });

  test('captura leituras, envia ao servidor e ao parar encerra a sessão sem sobrar nada', () async {
    final CaptureController controller = controllerFor(fakeCarScript());

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    expect(controller.status, CaptureStatus.capturing);
    await waitFor(() => controller.readingsCaptured >= 5);
    expect(controller.latest!.rpm, 1726);
    expect(controller.latest!.batteryVoltage, 14.2);

    await controller.stop();

    expect(controller.status, CaptureStatus.idle);
    expect(api.opened, <String>['sessao-teste']);
    expect(api.totalReadingsSent, controller.readingsCaptured);
    expect(store.pendingReadingCount('sessao-teste'), 0);
    expect(api.ended, <String>['sessao-teste']);
    expect(controller.pendingReadings, 0);
    expect(controller.readingsPerSecond, greaterThan(0));
  });

  test('as leituras seguem a ordem e não repetem o número de sequência', () async {
    final CaptureController controller = controllerFor(fakeCarScript());
    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 8);
    await controller.stop();

    final List<int> seqs = api.readingBatches.expand((List<int> b) => b).toList();
    expect(seqs.length, controller.readingsCaptured);
    expect(seqs, List<int>.generate(seqs.length, (int i) => i));
  });

  test('lê o P0043 do carro de teste e o envia como confirmado', () async {
    final CaptureController controller = controllerFor(fakeCarScript(stored: '43 01 00 43 00 00 00'));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.dtcs.isNotEmpty);
    await controller.stop();

    expect(controller.dtcs, <Dtc>[const Dtc(code: 'P0043', status: DtcStatus.stored)]);
    expect(api.dtcCodes, <String>['P0043/stored']);
  });

  test('o mesmo código lido várias vezes é gravado uma só vez', () async {
    final CaptureController controller = controllerFor(fakeCarScript(stored: '43 01 00 43 00 00 00'));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    controller.readDtcsSoon();
    controller.readDtcsSoon();
    await waitFor(() => controller.readingsCaptured >= 8);
    await controller.stop();

    expect(api.dtcCodes, <String>['P0043/stored']);
  });

  test('perda da conexão com o adaptador: encerra com erro, mas preserva e envia o que já capturou', () async {
    final Map<String, String> script = fakeCarScript();
    final CaptureController controller = controllerFor(script);

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    script.remove('010D'); // o adaptador deixa de responder à velocidade
    await waitFor(() => controller.status == CaptureStatus.error);

    expect(controller.errorMessage, contains('perdida'));
    expect(api.ended, <String>['sessao-teste']);
    expect(controller.pendingReadings, 0);
    expect(api.totalReadingsSent, controller.readingsCaptured);
  });

  test('falha ao conectar (ignição desligada): erro claro e nenhuma sessão criada', () async {
    final Map<String, String> script = fakeCarScript();
    script['0100'] = 'UNABLE TO CONNECT\r\r>';
    final CaptureController controller = controllerFor(script);

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');

    expect(controller.status, CaptureStatus.error);
    expect(controller.errorMessage, contains('ignição'));
    expect(store.sessions, isEmpty);
  });

  test('sem internet: continua capturando, guarda tudo e envia quando a rede volta', () async {
    api.failWith = const ApiUnavailableException();
    final CaptureController controller = controllerFor(fakeCarScript());

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 6);
    await controller.stop();

    expect(controller.status, CaptureStatus.idle);
    expect(store.pendingReadingCount('sessao-teste'), controller.readingsCaptured);
    expect(controller.lastSync!.stoppedBy, SyncStop.unavailable);
    expect(controller.pendingReadings, controller.readingsCaptured);

    api.failWith = null;
    await controller.syncNow();

    expect(store.pendingReadingCount('sessao-teste'), 0);
    expect(api.totalReadingsSent, controller.readingsCaptured);
    expect(api.ended, <String>['sessao-teste']);
  });

  test('login expirado durante a captura: não perde dados e avisa que precisa entrar de novo', () async {
    api.failWith = const ApiUnauthorizedException();
    final CaptureController controller = controllerFor(fakeCarScript());

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 4);
    await controller.stop();

    expect(controller.lastSync!.stoppedBy, SyncStop.unauthorized);
    expect(store.pendingReadingCount('sessao-teste'), controller.readingsCaptured);
  });
}
