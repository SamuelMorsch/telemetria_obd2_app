import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';

void main() {
  runApp(const TelemetriaApp());
}

class TelemetriaApp extends StatelessWidget {
  const TelemetriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Telemetria OBD-II',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BluetoothConnectionScreen(),
    );
  }
}

class BluetoothConnectionScreen extends StatefulWidget {
  const BluetoothConnectionScreen({super.key});

  @override
  State<BluetoothConnectionScreen> createState() => _BluetoothConnectionScreenState();
}

class _BluetoothConnectionScreenState extends State<BluetoothConnectionScreen> {
  final OBDService _obdService = OBDService();
  List<BluetoothDevice> _devicesList = [];
  bool _isLoadingDevices = true;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _devicesList = devices;
        _isLoadingDevices = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar dispositivos: $e");
    }
  }

  @override
  void dispose() {
    _obdService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnóstico OBD-II'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: _obdService.connectionStatus,
                  builder: (context, status, child) {
                    return Text(
                      status,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: status.contains("Lendo") ? Colors.green.shade700 : Colors.blue.shade900,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInstrumentPanel("RPM", _obdService.rpm, "rev/min"),
                    _buildInstrumentPanel("VELOCIDADE", _obdService.speed, "km/h"),
                  ],
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            color: Colors.grey.shade200,
            child: ValueListenableBuilder<String>(
              valueListenable: _obdService.rawDebug,
              builder: (context, raw, child) {
                return Text(
                  "Raw: $raw",
                  style: const TextStyle(fontSize: 12, color: Colors.black54, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                );
              },
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _isLoadingDevices
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              itemCount: _devicesList.length,
              itemBuilder: (context, index) {
                BluetoothDevice device = _devicesList[index];
                return ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(device.name ?? "Desconhecido"),
                  subtitle: Text(device.address),
                  trailing: ElevatedButton(
                    onPressed: () => _obdService.connect(device),
                    child: const Text('Conectar'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstrumentPanel(String label, ValueNotifier<int> notifier, String unit) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (context, value, child) {
            return Text(
              value.toString(),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
            );
          },
        ),
        Text(unit, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }
}