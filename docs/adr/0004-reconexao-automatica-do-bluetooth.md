# ADR 0004 - Reconexão automática do Bluetooth durante a captura

**Status:** aceita (verificada em testes automatizados e em carro real)

## Contexto
O sistema existe para acompanhar um carro **em movimento**, e é nele que o link Bluetooth entre o
celular e o adaptador OBD-II mais falha: o adaptador folga com a vibração, o celular troca de estado
de energia, o motorista desliga e liga o carro. Até aqui, uma queda encerrava a captura de duas formas:

- **Escrever num Bluetooth já desconectado** lança um erro da biblioteca, que não é do tipo OBD. Ele
  caía no tratamento genérico e a captura terminava na hora, com "Erro inesperado na captura".
- **Uma queda em silêncio** só era percebida depois de 3 respostas perdidas de 3 s cada (cerca de 9 s),
  e aí a captura também terminava.

Nos dois casos o resto da viagem se perdia, e o motorista teria de reiniciar a captura, o que abre
**outra sessão** e parte os dados em dois.

## Decisão
- **Detectar a queda na hora.** O `ElmClient` percebe o fim do fluxo de entrada e as falhas de escrita
  (com limite de tempo) e as converte em `ObdConnectionException`, sem esperar o tempo limite.
- **Reconectar sem encerrar a sessão.** Diante de uma `ObdConnectionException`, ou de 3 falhas
  seguidas, o `CaptureController` fecha a conexão antiga e abre outra pela mesma fábrica de conexão
  usada na partida (o adaptador é reiniciado e reconhecido de novo). A **sessão e a numeração das
  leituras continuam**: o servidor já descarta repetições pela chave (sessão, seq, horário).
- **Esperas crescentes entre as tentativas:** 2 s, 4 s, 8 s e depois 15 s. Cada tentativa tem um
  limite de 25 s, porque o Bluetooth pode ficar esperando por muito tempo.
- **Desistir só depois de 5 minutos sem nenhuma leitura.** Aí a captura termina com erro, a sessão é
  encerrada **no horário da última leitura recebida** (e não no momento da desistência) e tudo o que
  já foi capturado é enviado.
- **O usuário pode parar a qualquer momento**, inclusive no meio de uma tentativa, e a captura
  encerra normalmente. Se uma tentativa travada terminar depois, a conexão que ela abriu é fechada.
- **O envio da fila continua** durante a reconexão.
- **Mensagens curtas.** Os erros do Bluetooth do Android trazem a pilha Java inteira; a tela mostra só o motivo
  em uma frase (por exemplo, "o adaptador não respondeu (fora de alcance, desconectado ou sem energia)").
- **A tela avisa:** "Reconectando… (tentativa N)", um quadro de alerta com o horário da última leitura,
  valores antigos sem alerta de queda de tensão e o número de reconexões da captura.

## Consequências
- (+) A viagem continua numa **só sessão**, com uma lacuna onde não havia conexão.
- (+) A lógica é testável sem celular: os testes derrubam o transporte no meio da captura e conferem
  a continuidade da sessão, a ausência de leituras repetidas, a parada durante a reconexão, a
  desistência e o fechamento de conexões atrasadas.
- (-) Enquanto reconecta, não há leituras. O gráfico do painel pode ligar os dois lados da lacuna com
  uma linha reta; marcar a lacuna no gráfico fica como melhoria.
- (+) Verificada em carro real em três cenários: adaptador desconectado e encaixado de volta, Bluetooth do
  celular desligado e religado (nos dois a captura voltou sozinha) e adaptador que não volta (a captura
  terminou ao fim do tempo limite). Esses testes mostraram que a mensagem de erro crua do Android era
  longa demais para a tela, o que motivou as mensagens curtas.
- (-) Com a ignição desligada, o adaptador pode perder a energia e a reconexão não funciona; o app
  tenta por 5 minutos e então encerra.
