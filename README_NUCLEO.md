# Núcleo do app (lib/core)

Código **puro Dart**, sem Flutter, testável com `flutter test` sem celular nem adaptador.

| Pasta | O que faz |
|---|---|
| `core/models.dart` | `ObdValues`, `Reading` (com `toApiJson`), `Dtc` |
| `core/obd/elm_parser.dart` | Decodifica as respostas do ELM327: tensão, PIDs, códigos de falha (CAN e legado, mensagens longas, várias centrais) |
| `core/obd/elm_client.dart` | Envia um comando e espera a resposta completa (junta os pedaços do Bluetooth, trata timeout e erros) |
| `core/obd/obd_reader.dart` | Inicializa o adaptador, descobre o protocolo e os PIDs suportados, lê cada ciclo, lê/apaga códigos de falha |
| `core/obd/obd_transport.dart` | Interface do canal de bytes. O Bluetooth real entra aqui (próxima etapa) |
| `core/sync/outbox.dart` | Interfaces da fila local e do cliente da API |
| `core/sync/outbox_syncer.dart` | Envia a fila em lotes sem perder nem duplicar, com recuperação de falhas |

Decisões: Bluetooth atrás de uma interface (a biblioteca pode ser trocada sem tocar na lógica);
leitura de tensão por `ATRV` **e** pelo PID `01 42`; temperatura a cada 10 ciclos; envio em lotes
idempotentes (a API já deduplica por sessão, `seq` e horário).
