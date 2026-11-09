# Núcleo do app (`lib/core`)

Código **puro Dart**, sem Flutter, testável com `flutter test` sem celular nem adaptador.

| Arquivo | O que faz |
|---|---|
| `models.dart` | `ObdValues`, `Reading` (com `toApiJson`) e `Dtc` |
| `obd/elm_parser.dart` | Decodifica as respostas do ELM327: tensão, PIDs e códigos de falha (CAN e legado, mensagens longas, várias centrais) |
| `obd/elm_client.dart` | Envia um comando e espera a resposta completa (junta os pedaços do Bluetooth e trata timeout e erros) |
| `obd/obd_reader.dart` | Inicializa o adaptador, descobre o protocolo e os PIDs suportados, lê cada ciclo e lê ou apaga os códigos de falha |
| `obd/obd_transport.dart` | Interface do canal de bytes. O Bluetooth real fica em `lib/bluetooth/serial_transport.dart` |
| `obd/obd_exceptions.dart` | Erros do adaptador: timeout e erros do ELM327 |
| `sync/outbox.dart` | Interfaces da fila local e do cliente da API |
| `sync/outbox_syncer.dart` | Envia a fila em lotes sem perder nem duplicar, com recuperação de falhas |

**Decisões:**
- O Bluetooth fica atrás de uma interface, então a biblioteca pode ser trocada sem tocar na lógica.
- A tensão é lida por `ATRV` **e** pelo PID `01 42`, gravadas separadas, para poder comparar.
- A temperatura é lida a cada 10 ciclos.
- O envio é em lotes idempotentes: a API deduplica por sessão, `seq` e horário.

Mais contexto na [ADR 0001](../../docs/adr/0001-app-nucleo-testavel-fila-local-e-bluetooth-isolado.md).
