import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

/// Dispositivo Bluetooth, sem expor o tipo da biblioteca ao resto do app.
class BtDevice {
  const BtDevice({required this.name, required this.address, required this.bonded});

  final String name;
  final String address;
  final bool bonded;

  /// Adaptadores ELM327 costumam se chamar "OBDII", "OBD2", "V-LINK" ou "ELM327".
  bool get looksLikeObd {
    final String n = name.toUpperCase();
    return n.contains('OBD') || n.contains('ELM') || n.contains('V-LINK') || n.contains('VLINK');
  }
}

/// Permissões, ligar o Bluetooth, listar, procurar e parear dispositivos.
class BluetoothDevices {
  const BluetoothDevices();

  Future<bool> ensurePermissions() async {
    final Map<Permission, PermissionStatus> statuses = await <Permission>[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((PermissionStatus s) => s.isGranted);
  }

  Future<bool> ensureEnabled() async {
    final bool? enabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (enabled == true) return true;
    return (await FlutterBluetoothSerial.instance.requestEnable()) == true;
  }

  Future<List<BtDevice>> bonded() async {
    final List<BluetoothDevice> list = await FlutterBluetoothSerial.instance.getBondedDevices();
    return <BtDevice>[
      for (final BluetoothDevice d in list)
        BtDevice(name: d.name ?? d.address, address: d.address, bonded: true),
    ];
  }

  Stream<BtDevice> discover() {
    return FlutterBluetoothSerial.instance.startDiscovery().map(
          (BluetoothDiscoveryResult r) => BtDevice(
            name: r.device.name ?? r.device.address,
            address: r.device.address,
            bonded: r.device.isBonded,
          ),
        );
  }

  Future<void> stopDiscovery() => FlutterBluetoothSerial.instance.cancelDiscovery();

  /// Pareia (a senha do adaptador costuma ser 1234 ou 0000; o Android pergunta).
  Future<bool> bond(String address) async {
    return (await FlutterBluetoothSerial.instance.bondDeviceAtAddress(address)) == true;
  }
}
