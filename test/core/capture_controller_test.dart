import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:telemetria_obd2_app/capture/capture_controller.dart';
import 'package:telemetria_obd2_app/core/models.dart';
import 'package:telemetria_obd2_app/core/obd/elm_client.dart';
import 'package:telemetria_obd2_app/core/obd/obd_exceptions.dart';
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
    final ObdReader reader = ObdReader(
      client,
      settleAfterReset: Duration.zero,
      dtcTimeout: const Duration(milliseconds: 60),
      pendingDtcTimeout: const Duration(milliseconds: 60),
    );
    await reader.initialize();
    return ObdLink(reader: reader, close: client.close);
  };
}

/// Conexão que "funciona" nas [works] primeiras chamadas e depois recusa, como um adaptador que
/// saiu do alcance. Guarda os transportes criados, para o teste poder derrubar o Bluetooth.
LinkFactory flakyFactory(Map<String, String> script, List<ScriptedTransport> transports, {required int works}) {
  int calls = 0;
  return (String address) async {
    calls++;
    if (calls > works) throw ObdConnectionException('sem sinal do adaptador');
    final ScriptedTransport transport = ScriptedTransport(script);
    transports.add(transport);
    final ElmClient client = ElmClient(transport, defaultTimeout: const Duration(milliseconds: 60));
    final ObdReader reader = ObdReader(
      client,
      settleAfterReset: Duration.zero,
      dtcTimeout: const Duration(milliseconds: 60),
      pendingDtcTimeout: const Duration(milliseconds: 60),
    );
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
      reconnectBackoff: const Duration(milliseconds: 10),
      reconnectMaxBackoff: const Duration(milliseconds: 30),
      reconnectAttemptTimeout: const Duration(milliseconds: 150),
      reconnectGiveUpAfter: const Duration(milliseconds: 600),
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

  test('falha na leitura de códigos de falha NÃO derruba a captura de tensão', () async {
    final Map<String, String> script = fakeCarScript();
    script.remove('03'); // o adaptador não responde aos códigos de falha (timeout)
    final CaptureController controller = controllerFor(script);

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 8);
    await waitFor(() => controller.lastDtcError != null);

    expect(controller.status, CaptureStatus.capturing); // continua capturando
    expect(controller.lastDtcError, isNotNull);
    await controller.stop();

    expect(controller.status, CaptureStatus.idle);
    expect(controller.errorMessage, isNull);
    expect(api.totalReadingsSent, controller.readingsCaptured);
  });

  test('um erro na leitura de códigos não é repetido a cada ciclo (só a cada dtcEvery)', () async {
    final Map<String, String> script = fakeCarScript();
    script.remove('03');
    final CaptureController controller = controllerFor(script);

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.dtcReadsDone >= 1);
    await waitFor(() => controller.readingsCaptured >= 6);
    final int reads = controller.dtcReadsDone;
    await controller.stop();

    // Com dtcEvery de 80 ms e várias leituras de 60 ms de timeout, houve poucas tentativas,
    // e nunca uma por ciclo.
    expect(reads, lessThan(controller.readingsCaptured));
  });

  test('guarda a resposta bruta da leitura de códigos para exibir na tela', () async {
    final CaptureController controller = controllerFor(fakeCarScript(stored: '43 01 00 43 00 00 00'));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.dtcReadsDone >= 1);
    await controller.stop();

    expect(controller.lastDtcError, isNull);
    expect(controller.lastDtcReadAt, isNotNull);
    expect(controller.lastDtcRaw, contains('03 -> [43 01 00 43 00 00 00]'));
  });

  test('o Bluetooth cai no meio da captura: reconecta sozinho e continua a mesma sessão', () async {
    final Map<String, String> script = fakeCarScript();
    final List<ScriptedTransport> transports = <ScriptedTransport>[];
    final CaptureController controller = controllerFor(script, factory: flakyFactory(script, transports, works: 2));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    final int antes = controller.readingsCaptured;

    await transports.first.close(); // o Bluetooth cai
    await waitFor(() => controller.reconnections == 1);
    await waitFor(() => controller.readingsCaptured >= antes + 3);
    await controller.stop();

    expect(transports.length, 2);
    expect(controller.status, CaptureStatus.idle);
    expect(controller.errorMessage, isNull);
    expect(controller.reconnecting, isFalse);
    expect(api.opened, <String>['sessao-teste']); // continuou a mesma sessão
    final List<int> seqs = api.readingBatches.expand((List<int> b) => b).toList();
    expect(seqs, List<int>.generate(seqs.length, (int i) => i)); // sem buracos nem repetições
    expect(seqs.length, controller.readingsCaptured);
    expect(api.ended, <String>['sessao-teste']);
  });

  test('parar durante a reconexão encerra normalmente, sem erro', () async {
    final Map<String, String> script = fakeCarScript();
    final List<ScriptedTransport> transports = <ScriptedTransport>[];
    final CaptureController controller = controllerFor(script, factory: flakyFactory(script, transports, works: 1));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    await transports.first.close();
    await waitFor(() => controller.reconnecting);
    await controller.stop();

    expect(controller.status, CaptureStatus.idle);
    expect(controller.errorMessage, isNull);
    expect(controller.reconnecting, isFalse);
    expect(api.ended, <String>['sessao-teste']);
  });

  test('sem conseguir reconectar a tempo, encerra com erro e a sessão termina na última leitura', () async {
    final Map<String, String> script = fakeCarScript();
    final List<ScriptedTransport> transports = <ScriptedTransport>[];
    final CaptureController controller = controllerFor(script, factory: flakyFactory(script, transports, works: 1));

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    await transports.first.close();
    await waitFor(() => controller.status == CaptureStatus.error);

    expect(controller.errorMessage, contains('perdida'));
    expect(controller.reconnecting, isFalse);
    expect(store.sessions['sessao-teste']!.endedAt, controller.lastReadingAt);
    expect(api.ended, <String>['sessao-teste']);
    expect(controller.pendingReadings, 0); // nada se perde
    expect(api.totalReadingsSent, controller.readingsCaptured);
  });

  test('tentativa de conexão que trava e termina tarde é fechada, sem deixar a conexão aberta', () async {
    final Map<String, String> script = fakeCarScript();
    final List<ScriptedTransport> transports = <ScriptedTransport>[];
    final LinkFactory good = flakyFactory(script, transports, works: 99);
    final Completer<ObdLink> hung = Completer<ObdLink>();
    bool lateClosed = false;
    int calls = 0;
    Future<ObdLink> factory(String address) {
      calls++;
      if (calls == 2) return hung.future; // a 1ª tentativa de reconexão trava
      return good(address);
    }

    final CaptureController controller = controllerFor(script, factory: factory);

    await controller.start(vehicleId: 'v1', deviceAddress: 'AA:BB');
    await waitFor(() => controller.readingsCaptured >= 3);
    await transports.first.close();
    await waitFor(() => controller.reconnections == 1); // a 2ª tentativa deu certo

    final ObdLink late = await carFactory(script)('AA:BB');
    hung.complete(ObdLink(
      reader: late.reader,
      close: () async {
        lateClosed = true;
        await late.close();
      },
    ));
    await waitFor(() => lateClosed);
    await controller.stop();

    expect(controller.errorMessage, isNull);
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
