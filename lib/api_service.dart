import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database_helper.dart';

class ApiService {
  // IP da instância EC2 na AWS configurada para produção
  static const String baseUrl = 'http://15.229.77.63:3000/api';

  static Future<void> sincronizarComNuvem() async {
    try {
      // 1. Busca as falhas salvas no SQLite
      final falhas = await DatabaseHelper.instance.listarFalhas();

      if (falhas.isEmpty) {
        print("Nenhuma falha para sincronizar.");
        return;
      }

      // 2. Monta o pacote JSON
      final pacote = jsonEncode({
        "data_sincronizacao": DateTime.now().toIso8601String(),
        "falhas": falhas
      });

      // 3. Dispara para a API Node.js rodando na AWS
      final resposta = await http.post(
        Uri.parse('$baseUrl/sincronizar'),
        headers: {"Content-Type": "application/json"},
        body: pacote,
      );

      // 4. Verifica se o servidor respondeu com 201 (Created)
      if (resposta.statusCode == 201) {
        print("Dados enviados com sucesso para a AWS!");
        // Limpa o histórico local após confirmar que a nuvem recebeu
        await DatabaseHelper.instance.limparHistorico();
      } else {
        print("Erro do servidor: ${resposta.body}");
      }
    } catch (e) {
      print("Falha na conexão com a internet ou servidor offline: $e");
    }
  }
}