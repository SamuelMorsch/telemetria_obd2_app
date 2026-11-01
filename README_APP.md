# Telemetria Automotiva Remota - App Android

Lê o veículo pelo adaptador OBD-II (ELM327, Bluetooth clássico) e envia a tensão elétrica, a rotação,
a velocidade, a temperatura e os códigos de falha ao servidor da oficina, em tempo real, mesmo com
o sinal do celular indo e voltando.

## Como usar
1. Entre com a conta da oficina.
2. Escolha (ou cadastre) o veículo.
3. Ligue o carro com o adaptador conectado, toque em **Escolher** e selecione o "OBDII".
4. **Iniciar captura**. Mantenha o app aberto (a tela fica ligada).

## Estrutura
`lib/core`: decodificação do ELM327, leitor OBD e fila de envio (testáveis sem celular) ·
`lib/capture`: controle da captura · `lib/data`: SQLite e cliente do servidor ·
`lib/bluetooth`: Bluetooth (isolado) · `lib/screens`: telas. Decisões em `docs/adr`.

## Testes
```
flutter test
```
## Outro servidor
```
flutter run --dart-define=API_URL=https://meu-servidor
```
