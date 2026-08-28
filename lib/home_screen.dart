import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'obd_service.dart';
import 'historico_screen.dart';
import 'custom_gauge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OBDService _obdService = OBDService();
  List<BluetoothDevice> _devicesList = [];
  bool _isLoadingDevices = true;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    await [Permission.bluetooth, Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    try {
      List<BluetoothDevice> devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() { _devicesList = devices; _isLoadingDevices = false; });
    } catch (e) {
      debugPrint("Erro Bluetooth: $e");
    }
  }

  @override
  void dispose() {
    _obdService.disconnect();
    super.dispose();
  }

  // Define a cor da pílula baseada no status da conexão
  Color _getStatusColor(String status) {
    if (status.contains("Lendo") || status.contains("Conectado no protocolo")) return Colors.greenAccent;
    if (status.contains("Desconectado") || status.contains("Falha")) return Colors.redAccent;
    return Colors.amberAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PAINEL DE CONTROLE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 28),
            tooltip: "Histórico de Falhas",
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => HistoricoScreen(obdService: _obdService)));
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              // 1. Pílula de Status da Conexão
              Center(
                child: ValueListenableBuilder<String>(
                  valueListenable: _obdService.connectionStatus,
                  builder: (context, status, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _getStatusColor(status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: _getStatusColor(status).withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bluetooth_connected, size: 16, color: _getStatusColor(status)),
                          const SizedBox(width: 8),
                          Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: _getStatusColor(status),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // 2. Painel de Instrumentos (Card Moderno)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: _obdService.rpm,
                        builder: (context, rpmValue, child) => CustomGauge(
                          label: "RPM",
                          value: rpmValue.toDouble(),
                          max: 8000,
                          unit: "rev/min",
                          primaryColor: rpmValue > 5000 ? Colors.redAccent : const Color(0xFF38BDF8),
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: _obdService.speed,
                        builder: (context, speedValue, child) => CustomGauge(
                          label: "VELOCIDADE",
                          value: speedValue.toDouble(),
                          max: 220,
                          unit: "km/h",
                          primaryColor: const Color(0xFFFACC15), // Amarelo vibrante
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Painel de Diagnóstico Automático (Alerta Visual)
              ValueListenableBuilder<List<String>>(
                valueListenable: _obdService.faultCodes,
                builder: (context, codes, child) {
                  bool hasError = codes.isNotEmpty && codes.first != "Nenhuma falha detectada";
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: hasError ? Colors.redAccent.withOpacity(0.15) : Colors.greenAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: hasError ? Colors.redAccent : Colors.greenAccent.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasError ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                          color: hasError ? Colors.redAccent : Colors.greenAccent,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "STATUS DA ECU",
                                style: TextStyle(
                                  color: hasError ? Colors.redAccent : Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                codes.join(", "),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // 4. Seção de Conexão com o Veículo
              const Text(
                "VEÍCULOS PAREADOS",
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12),
              ),
              const SizedBox(height: 10),

              Expanded(
                child: _isLoadingDevices
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
                    : ListView.builder(
                  itemCount: _devicesList.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: const Color(0xFF1E293B).withOpacity(0.7), // Fundo levemente translúcido
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF38BDF8).withOpacity(0.2),
                          child: const Icon(Icons.directions_car, color: Color(0xFF38BDF8)),
                        ),
                        title: Text(
                          _devicesList[index].name ?? "Desconhecido",
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        subtitle: Text(
                          _devicesList[index].address,
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        trailing: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF38BDF8),
                            backgroundColor: const Color(0xFF38BDF8).withOpacity(0.1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () => _obdService.connect(_devicesList[index]),
                          child: const Text('Conectar'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}