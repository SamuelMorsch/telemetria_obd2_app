import 'package:flutter/material.dart';

import '../app_services.dart';
import '../bluetooth/bluetooth_devices.dart';
import '../core/sync/outbox.dart';
import '../core/sync/outbox_syncer.dart';
import '../data/backend_client.dart';
import 'capture_screen.dart';
import 'device_picker_screen.dart';

/// Escolha do veículo e do adaptador, e início da captura.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AppServices _services = AppServices.instance;

  List<VehicleInfo> _vehicles = <VehicleInfo>[];
  String? _vehicleId;
  BtDevice? _device;
  int _pending = 0;
  int _pendingDtcs = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String? savedVehicle = await _services.store.getValue('vehicle_id');
      final String? address = await _services.store.getValue('device_address');
      final String? name = await _services.store.getValue('device_name');
      final int pending = await _services.store.pendingReadingCount();
      final int pendingDtcs = await _services.store.pendingDtcCount();
      List<VehicleInfo> vehicles = _vehicles;
      String? error;
      try {
        vehicles = await _services.backend.vehicles();
      } on ApiUnauthorizedException {
        await _services.logout();
        return;
      } catch (e) {
        error = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _vehicleId = vehicles.any((VehicleInfo v) => v.id == savedVehicle) ? savedVehicle : null;
        _device = address == null ? null : BtDevice(name: name ?? address, address: address, bonded: true);
        _pending = pending;
        _pendingDtcs = pendingDtcs;
        _error = error;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectVehicle(VehicleInfo vehicle) async {
    setState(() => _vehicleId = vehicle.id);
    await _services.store.setValue('vehicle_id', vehicle.id);
  }

  Future<void> _newVehicle() async {
    final TextEditingController plate = TextEditingController();
    final TextEditingController model = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Novo veículo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa (ABC-1D23)')),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo (opcional)')),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cadastrar')),
        ],
      ),
    );
    final String plateText = plate.text.trim();
    final String modelText = model.text.trim();
    plate.dispose();
    model.dispose();
    if (ok != true || plateText.isEmpty) return;

    try {
      final VehicleInfo created = await _services.backend.createVehicle(plate: plateText, model: modelText);
      await _services.store.setValue('vehicle_id', created.id);
      await _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _pickDevice() async {
    final BtDevice? device = await Navigator.of(context).push<BtDevice>(
      MaterialPageRoute<BtDevice>(builder: (BuildContext context) => const DevicePickerScreen()),
    );
    if (device == null) return;
    await _services.store.setValue('device_address', device.address);
    await _services.store.setValue('device_name', device.name);
    if (mounted) setState(() => _device = device);
  }

  Future<void> _start() async {
    final VehicleInfo vehicle = _vehicles.firstWhere((VehicleInfo v) => v.id == _vehicleId);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CaptureScreen(vehicle: vehicle, device: _device!),
      ),
    );
    if (!mounted) return;
    await _refreshPending();
  }

  Future<void> _refreshPending() async {
    final int pending = await _services.store.pendingReadingCount();
    final int pendingDtcs = await _services.store.pendingDtcCount();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _pendingDtcs = pendingDtcs;
    });
  }

  Future<void> _syncNow() async {
    final SyncResult result = await _services.syncer.syncOnce();
    await _refreshPending();
    if (!mounted) return;
    if (result.stoppedBy == SyncStop.unauthorized) {
      _snack('Seu login expirou. Entre de novo para enviar.');
      await _services.logout();
    } else if (result.stoppedBy == SyncStop.unavailable) {
      _snack('Sem conexão com o servidor. Tente de novo mais tarde.');
    } else {
      _snack('Enviado: ${result.readingsSent} leituras e ${result.dtcsSent} códigos de falha.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final bool canStart = _vehicleId != null && _device != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Telemetria Automotiva'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => _services.logout(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text(_services.user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text('1. Veículo', style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              if (_services.user?.canRegisterVehicles ?? false)
                                TextButton.icon(
                                  onPressed: _newVehicle,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Novo'),
                                ),
                            ],
                          ),
                          if (_vehicles.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text('Nenhum veículo cadastrado.'),
                            ),
                          for (final VehicleInfo v in _vehicles)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(v.label),
                              selected: v.id == _vehicleId,
                              trailing: v.id == _vehicleId ? const Icon(Icons.check_circle) : null,
                              onTap: () => _selectVehicle(v),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('2. Adaptador OBD-II'),
                      subtitle: Text(_device == null ? 'Nenhum escolhido' : '${_device!.name}\n${_device!.address}'),
                      isThreeLine: _device != null,
                      trailing: OutlinedButton(onPressed: _pickDevice, child: const Text('Escolher')),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: canStart ? _start : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Iniciar captura'),
                  ),
                  if (!canStart)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Escolha o veículo e o adaptador para começar.'),
                    ),
                  const SizedBox(height: 24),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        _pending + _pendingDtcs == 0 ? Icons.cloud_done : Icons.cloud_upload,
                        color: _pending + _pendingDtcs == 0 ? Colors.green : null,
                      ),
                      title: Text(
                        _pending + _pendingDtcs == 0
                            ? 'Tudo enviado'
                            : '$_pending leituras e $_pendingDtcs códigos de falha aguardando envio',
                      ),
                      subtitle: Text(
                        _pending + _pendingDtcs == 0
                            ? 'Nada pendente no celular: o que foi capturado já está no painel da oficina.'
                            : 'Ficam guardados no celular até o servidor confirmar o recebimento.',
                      ),
                      trailing: OutlinedButton(onPressed: _syncNow, child: const Text('Enviar agora')),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
