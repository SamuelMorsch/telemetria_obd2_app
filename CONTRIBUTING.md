# Como contribuir

Obrigado pelo interesse! Este repositório é o aplicativo Android do sistema de telemetria automotiva
remota (veja o [README](README.md) deste módulo e o
[README principal](https://github.com/SamuelMorsch/telemetria-api) do sistema).

## Preparando o ambiente
Requer Flutter 3.44 e JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
```
Os testes não precisam de celular nem de adaptador OBD-II.

## Fluxo de trabalho
1. Crie uma branch a partir da `main`, com um nome que diga o que muda (`feat/...`, `fix/...`).
2. Faça as alterações **com testes** quando mudar comportamento.
3. Mensagens de commit seguem o padrão do histórico: `feat:`, `fix:`, `ci:`, `docs:`,
   `refactor:`, `build:` ou `chore:`, seguido de uma frase curta.
4. Abra um Pull Request para a `main`. Ele só deve ser juntado quando o **CI** estiver verde
   (análise, testes e APK) e o **SonarQube Cloud** não apontar problemas novos.
5. Mudanças de arquitetura relevantes ganham uma nova [ADR](docs/adr).

## Observações
- O código em `third_party/` é de terceiros (ver [ADR 0002](docs/adr/0002-plugin-bluetooth-mantido-no-repositorio.md)) e não passa pela análise.
- Mudanças que afetam a leitura do adaptador só ficam totalmente validadas com um carro real.
- Para relatar uma vulnerabilidade, escreva para samuel.morsch@catolicasc.edu.br em vez de abrir uma issue pública.
