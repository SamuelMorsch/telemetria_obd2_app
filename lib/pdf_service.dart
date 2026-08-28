import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'database_helper.dart';

class PdfService {
  static Future<void> gerarECompartilharRelatorio() async {
    final falhas = await DatabaseHelper.instance.listarFalhas();

    if (falhas.isEmpty) return; // Não gera PDF se não tiver falha

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Cabeçalho
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('LAUDO DE DIAGNÓSTICO OBD-II', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.Text(
                      'Data: ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Informações do Veículo (Pode ser dinâmico no futuro)
              pw.Text('Status do Sistema: Falhas Detectadas', style: pw.TextStyle(fontSize: 14, color: PdfColors.red800)),
              pw.SizedBox(height: 20),

              // Tabela de Falhas
              pw.Table.fromTextArray(
                headers: ['Código da Falha', 'Data e Hora da Detecção'],
                data: falhas.map((f) => [
                  f['codigo'],
                  f['timestamp'].toString().substring(0, 19).replaceAll('T', ' às ')
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                },
              ),

              pw.Spacer(),

              // Rodapé
              pw.Divider(),
              pw.Center(
                child: pw.Text(
                  'Relatório gerado automaticamente pelo Sistema de Telemetria Avançada',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Abre a janela nativa do celular para compartilhar o PDF gerado
    await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'laudo_diagnostico_${DateTime.now().millisecondsSinceEpoch}.pdf'
    );
  }
}