import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_services.dart';
import '../bluetooth/bluetooth_devices.dart';
import '../capture/capture_controller.dart';
import '../core/models.dart';
import '../core/sync/outbox_syncer.dart';
import '../data/backend_client.dart';

/// Captura em andamento: valores ao vivo, códigos de falha e situação do envio.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.vehicle, required this.device});

  final VehicleInfo vehicle;
  final BtDevice device;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureController _controller = AppServices.instance.createCaptureController();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // mantém a tela ligada durante a captura
    _controller.addListener(_onChanged);
    // Começa depois do primeiro quadro: o controle avisa a tela a cada mudança, e isso não pode
    // acontecer no meio da construção dela.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _begin();
    });
  }

  void _begin() {
    _controller.start(vehicleId: widget.vehicle.id, deviceAddress: widget.device.address);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmExit() async {
    final bool? stop = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Parar a captura?'),
        content: const Text('A sessão será encerrada e o que sobrou será enviado ao servidor.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Parar e sair')),
        ],
      ),
    );
    if (stop != true) return;
    await _controller.stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _fmt(num? value, {int digits = 0}) => value == null ? '—' : value.toStringAsFixed(digits);

  String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _statusText() {
    switch (_controller.status) {
      case CaptureStatus.idle:
        return 'Captura encerrada';
      case CaptureStatus.connecting:
        return 'Conectando ao adaptador…';
      case CaptureStatus.capturing:
        return 'Capturando';
      case CaptureStatus.stopping:
        return 'Encerrando e enviando…';
      case CaptureStatus.error:
        return 'Erro';
    }
  }

  String _syncText() {
    final SyncResult? sync = _controller.lastSync;
    if (_controller.lastSyncError != null) return 'Erro no envio: ${_controller.lastSyncError}';
    if (sync == null) return 'Aguardando o primeiro envio…';
    final String at = _controller.lastSyncAt == null ? '' : ' às ${_time(_controller.lastSyncAt!)}';
    switch (sync.stoppedBy) {
      case null:
        return 'Enviado$at';
      case SyncStop.unavailable:
        return 'Sem conexão com o servidor$at (guardando no celular)';
      case SyncStop.unauthorized:
        return 'Login expirado: entre de novo para enviar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final CaptureController c = _controller;
    final ObdValues? v = c.latest;
    final bool lowVoltage = v != null &&
        v.batteryVoltage != null &&
        v.rpm != null &&
        v.rpm! >= 700 &&
        v.batteryVoltage! < 13.0;

    return PopScope(
      canPop: !c.isActive,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.vehicle.plate)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                Chip(
                  avatar: Icon(
                    c.status == CaptureStatus.capturing ? Icons.fiber_manual_record : Icons.circle_outlined,
                    color: c.status == CaptureStatus.capturing ? Colors.green : null,
                    size: 16,
                  ),
                  label: Text(_statusText()),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.device.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            if (c.status == CaptureStatus.error && c.errorMessage != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(12), child: Text(c.errorMessage!)),
              ),
            if (lowVoltage)
              Card(
                color: Colors.red.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Queda de tensão: ${_fmt(v.batteryVoltage, digits: 2)} V com o motor a ${_fmt(v.rpm)} rpm',
                    style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: <Widget>[
                _Stat(label: 'Tensão (adaptador)', value: _fmt(v?.batteryVoltage, digits: 2), unit: 'V', alert: lowVoltage),
                _Stat(label: 'Tensão (central)', value: _fmt(v?.controlModuleVoltage, digits: 2), unit: 'V'),
                _Stat(label: 'Rotação', value: _fmt(v?.rpm), unit: 'rpm'),
                _Stat(label: 'Velocidade', value: _fmt(v?.speedKmh), unit: 'km/h'),
                _Stat(label: 'Temp. do motor', value: _fmt(v?.coolantTempC), unit: '°C'),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                dense: true,
                title: Text('${c.readingsCaptured} leituras · ${c.readingsPerSecond.toStringAsFixed(1)} por segundo'),
                subtitle: Text('${c.pendingReadings} aguardando envio\n${_syncText()}'),
                isThreeLine: true,
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text('Códigos de falha (${c.dtcs.length})', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton(
                          onPressed: c.status == CaptureStatus.capturing ? c.readDtcsSoon : null,
                          child: const Text('Ler agora'),
                        ),
                      ],
                    ),
                    if (c.dtcs.isEmpty) const Text('Nenhum código de falha registrado pelo veículo.'),
                    for (final Dtc d in c.dtcs)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.warning_amber, color: d.status == DtcStatus.pending ? Colors.orange : Colors.red),
                        title: Text(d.code, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(d.status == DtcStatus.pending ? 'Pendente (ainda não confirmado)' : 'Confirmado'),
                      ),
                    const Text(
                      'A descrição de cada código aparece no painel da oficina.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (c.status == CaptureStatus.capturing)
              FilledButton.icon(
                onPressed: _confirmExit,
                icon: const Icon(Icons.stop),
                label: const Text('Parar captura'),
              ),
            if (c.status == CaptureStatus.error || c.status == CaptureStatus.idle) ...<Widget>[
              FilledButton.icon(onPressed: _begin, icon: const Icon(Icons.refresh), label: const Text('Conectar de novo')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit, this.alert = false});

  final String label;
  final String value;
  final String unit;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: alert ? Colors.red.shade100 : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '$value $unit',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: alert ? Colors.red.shade900 : null),
            ),
          ],
        ),
      ),
    );
  }
}
