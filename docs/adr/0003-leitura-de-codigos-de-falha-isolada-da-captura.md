# ADR 0003 - Leitura de códigos de falha isolada da captura de tensão

**Status:** aceita

## Contexto
O objetivo do projeto é capturar a tensão e a rotação com o carro em movimento. Os códigos de falha
(DTC) são um complemento, mas a leitura deles era feita no mesmo ciclo e com o mesmo tratamento de
erro da tensão. Isso trazia três problemas:
- um adaptador que não responde ao serviço 07 (pendentes), ou responde devagar, fazia a leitura
  falhar, e três falhas seguidas encerravam a captura com "conexão perdida";
- como o horário da última leitura só era atualizado em caso de sucesso, a falha era repetida a cada
  volta do ciclo, cada uma esperando até 8 s;
- a tela mostrava "Nenhum código de falha" mesmo quando nenhuma leitura tinha sido feita.

Na primeira captura em carro real, as duas centrais responderam `43 00` e `47 00` ("0 códigos").
Não havia como saber, olhando a tela, se isso era a resposta do carro ou um problema de comunicação.

## Decisão
- A leitura de DTC tem **tratamento de erro próprio**: uma falha nela não conta como perda de
  conexão e não derruba a captura de tensão.
- A leitura é repetida só a cada 30 s ou pelo botão **Ler agora**, mesmo depois de uma falha.
- O serviço 07 é **opcional**, com timeout menor (3 s): se o adaptador não o suporta, seguimos só
  com os códigos confirmados (serviço 03).
- A resposta bruta do adaptador à última leitura é guardada e exibida na tela de captura
  (por exemplo, `03 -> [4300 | 4300] | 07 -> [4700 | 4700]`), para diagnóstico em campo.
- A tela distingue três estados: "Códigos ainda não lidos", "Não foi possível ler os códigos" e
  "Nenhum código de falha registrado pelo veículo".
- O escopo continua o **OBD-II padrão** (serviços 03 e 07): motor, câmbio e emissões.

## Consequências
- (+) A tensão e a rotação continuam sendo capturadas mesmo que a leitura de DTC falhe.
- (+) Em campo, o texto bruto mostra se "zero códigos" é a resposta do carro ou um erro.
- (-) Falhas de outros módulos (freios, airbag, carroceria) não são lidas: exigiriam protocolos
  específicos de cada montadora. Fica registrado como limitação.
- (-) Uma leitura de DTC lenta ainda pode atrasar um ciclo de tensão em alguns segundos, no pior caso.
