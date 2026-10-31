# ADR 0001 - App: núcleo testável, fila local e Bluetooth isolado

**Status:** aceita

## Contexto
O app v1 misturava Bluetooth, leitura do adaptador, tela e envio num mesmo lugar: difícil de testar sem
um carro, e qualquer falha de rede podia perder leituras. A v2 precisa capturar a tensão com o carro
em movimento, onde o sinal do celular some e volta.

## Decisão
- **Núcleo em Dart puro** (`lib/core`): decodificação do ELM327, cliente de comandos, leitor OBD e
  fila de envio. Não depende de Flutter nem de Bluetooth, então roda em `flutter test` com um adaptador
  de mentira (respostas combinadas, entregues em pedaços como o Bluetooth faz).
- **Bluetooth atrás de uma interface (`ObdTransport`)**, implementada em um único arquivo. A biblioteca
  `flutter_bluetooth_serial` já funcionou com o adaptador do projeto; se precisar ser trocada, só esse
  arquivo muda.
- **Tudo é gravado no SQLite antes de ser enviado** e só é apagado depois que o servidor confirma. O envio
  é em lotes idempotentes (a API deduplica por sessão, número de sequência e horário), então repetir um
  envio nunca duplica dados. Sem rede, a captura continua e o envio retoma depois.
- **Duas fontes de tensão**: `ATRV` (medida no conector OBD) e o PID `01 42` (informada pela central),
  gravadas separadas, o que permite comparar e detectar um adaptador impreciso.
- **Códigos de falha confirmados e pendentes** (serviços 03 e 07), com tratamento do byte de contagem
  das redes CAN e de mensagens longas.
- **Login no próprio banco local**, não em armazenamento criptografado do sistema: dentro da área privada
  do app, e com validade curta no servidor (8 h). Compromisso aceito para o escopo do TCC.
- **Erros do servidor traduzidos para três ações**: login expirado (pede novo login, preserva os dados),
  falha temporária (tenta depois, preserva os dados) e recusa definitiva (descarta só o item inválido).
  Um 404 em leituras NÃO descarta dados.

## Consequências
- (+) Lógica crítica verificada sem hardware; falhas de rede não perdem leituras.
- (+) O app abre uma sessão encerrada de forma segura mesmo se o sistema o fechar no meio da captura.
- (-) Sem serviço em primeiro plano ainda: a captura exige a tela ligada (próxima etapa).
