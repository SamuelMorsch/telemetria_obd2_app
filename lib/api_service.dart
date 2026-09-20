import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class ApiService {
  static const String baseUrl = 'https://api-telemetria-tcc.onrender.com/api';

  static Future<void> sincronizarComNuvem() async {
    try {
      // 1. Busca as falhas salvas no SQLite
      final falhas = await DatabaseHelper.instance.listarFalhas();

      if (falhas.isEmpty) {
        print("Nenhuma falha para sincronizar.");
        return;
      }

      // 2. Monta o pacote JSON no mesmo formato que testamos no Thunder Client
      final pacote = jsonEncode({
        "data_sincronizacao": DateTime.now().toIso8601String(),
        "falhas": falhas
      });

      // 3. Dispara para o Servidor Node.js
      final resposta = await http.post(
        Uri.parse('$baseUrl/sincronizar'),
        headers: {"Content-Type": "application/json"},
        body: pacote,
      );

      // 4. Verifica se o servidor respondeu com 201 (Created)
      if (resposta.statusCode == 201) {
        print("Dados enviados com sucesso para a nuvem!");
        // Opcional: Limpar o histórico local após confirmar que a nuvem recebeu
        await DatabaseHelper.instance.limparHistorico();
      } else {
        print("Erro do servidor: ${resposta.body}");
      }
    } catch (e) {
      print("Falha na conexão com a internet ou servidor offline: $e");
    }
  }
}