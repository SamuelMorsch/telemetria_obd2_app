import 'dart:async';

import 'package:flutter/material.dart';

import '../app_services.dart';
import '../bluetooth/bluetooth_devices.dart';

/// Lista os dispositivos Bluetooth (já pareados e próximos). Ao tocar em um, pareia se preciso
/// e devolve o escolhido.
class DevicePickerScreen extends StatefulWidget {
  const DevicePickerScreen({super.key});

  @override
  State<DevicePickerScreen> createState() => _DevicePickerScreenState();
}

class _DevicePickerScreenState extends State<DevicePickerScreen> {
  final BluetoothDevices _bt = AppServices.instance.bluetooth;
  final Map<String, BtDevice> _devices = <String, BtDevice>{};
  StreamSubscription<BtDevice>? _subscription;
  bool _scanning = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bt.stopDiscovery().catchError((Object _) {});
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _bt.ensurePermissions()) {
        setState(() => _error = 'Permita o acesso ao Bluetooth (e à localização) para procurar o adaptador.');
        return;
      }
      if (!await _bt.ensureEnabled()) {
        setState(() => _error = 'O Bluetooth precisa estar ligado.');
        return;
      }
      final List<BtDevice> bonded = await _bt.bonded();
      if (!mounted) return;
      setState(() {
        for (final BtDevice d in bonded) {
          _devices[d.address] = d;
        }
      });
      _scan();
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível usar o Bluetooth: $e');
    }
  }

  void _scan() {
    _subscription?.cancel();
    setState(() {
      _scanning = true;
      _error = null;
    });
    _subscription = _bt.discover().listen(
      (BtDevice d) {
        if (mounted) setState(() => _devices[d.address] = d);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _scanning = false;
            _error = 'Erro ao procurar dispositivos: $e';
          });
        }
      },
    );
  }

  Future<void> _select(BtDevice device) async {
    var chosen = device;
    if (!device.bonded) {
      setState(() => _busy = true);
      final bool ok = await _bt.bond(device.address);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível parear. A senha do adaptador costuma ser 1234 ou 0000.')),
        );
        return;
      }
      chosen = BtDevice(name: device.name, address: device.address, bonded: true);
    }
    if (mounted) Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final List<BtDevice> list = _devices.values.toList()
      ..sort((BtDevice a, BtDevice b) {
        if (a.looksLikeObd != b.looksLikeObd) return a.looksLikeObd ? -1 : 1;
        if (a.bonded != b.bonded) return a.bonded ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escolher adaptador'),
        actions: <Widget>[
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(tooltip: 'Procurar de novo', icon: const Icon(Icons.refresh), onPressed: _scan),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Ligue o carro com o adaptador conectado e toque em "OBDII" (ou o nome do seu adaptador).'),
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (final BtDevice d in list)
                  ListTile(
                    leading: Icon(d.looksLikeObd ? Icons.directions_car : Icons.bluetooth),
                    title: Text(d.name),
                    subtitle: Text('${d.address}${d.bonded ? ' · pareado' : ''}'),
                    onTap: _busy ? null : () => _select(d),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
