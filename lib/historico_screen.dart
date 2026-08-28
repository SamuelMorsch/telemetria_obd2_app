import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'obd_service.dart'; // Precisa importar para usar o clearDTCs
import 'pdf_service.dart';

class HistoricoScreen extends StatefulWidget {
  final OBDService obdService; // Recebemos o serviço por parâmetro

  const HistoricoScreen({super.key, required this.obdService});

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {

  void _atualizarTela() {
    setState(() {}); // Força o FutureBuilder a rodar de novo
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Histórico de Falhas"),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
            tooltip: "Gerar Relatório PDF",
            onPressed: () async {
              // Chama o gerador de PDF
              await PdfService.gerarECompartilharRelatorio();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DatabaseHelper.instance.listarFalhas(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text("O histórico está limpo.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                  );
                }

                final falhas = snapshot.data!;
                return ListView.builder(
                  itemCount: falhas.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.warning, color: Colors.red, size: 36),
                        title: Text(
                          "Código: ${falhas[index]['codigo']}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Text("Detectado em: ${falhas[index]['timestamp']}"),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Painel de botões de Ação Profissionais
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep, color: Colors.grey),
                    label: const Text("Limpar App", style: TextStyle(color: Colors.grey)),
                    onPressed: () async {
                      await DatabaseHelper.instance.limparHistorico();
                      _atualizarTela();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Histórico do celular apagado!")),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.car_repair, color: Colors.white),
                    label: const Text("Apagar ECU", style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                    onPressed: () async {
                      await widget.obdService.clearDTCs();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Comando enviado para apagar luz do painel!")),
                      );
                    },
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}