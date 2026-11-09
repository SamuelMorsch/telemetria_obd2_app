# ADR 0002 - Plugin Bluetooth mantido no repositório

**Status:** aceita

## Contexto
O app usa o `flutter_bluetooth_serial` 0.4.0, plugin de Bluetooth **clássico** (SPP) que já
funcionou com o adaptador do projeto. A última versão publicada é de agosto de 2021 e a configuração
Android dela usa `jcenter()`, repositório desativado e removido no Gradle 9, além de não declarar o
`namespace` exigido pelas versões atuais do Android Gradle Plugin.

O app compilava na máquina de desenvolvimento porque a cópia do plugin na cache do Dart tinha sido
**editada à mão**. Quando o CI tentou gerar o APK de release a partir de uma cópia limpa, o build
falhou. Ou seja, o app só compilava em um computador, o que impede builds reproduzíveis.

## Decisão
- Copiar o plugin para `third_party/flutter_bluetooth_serial`, com as mesmas alterações que já
  funcionavam: `jcenter()` trocado por `mavenCentral()`, Kotlin 1.8.0, `namespace` e
  `compileSdkVersion 34`, e limite superior do Dart ampliado. O código Dart e Java **não foi
  modificado**.
- Apontar o `pubspec.yaml` para essa pasta (`path:`), manter o arquivo `LICENSE` (MIT) do autor e
  documentar a origem e as alterações em `third_party/flutter_bluetooth_serial/VENDORED.md`.
- Excluir `third_party/` da análise estática e do SonarQube Cloud, por ser código de terceiros.
- No `android/app/build.gradle.kts`, desativar `dependenciesInfo`: o metadado extra que a Play Store
  lê quebrava o build de release com Gradle 9.1 e AGP 9, e este app não é publicado na loja.

## Consequências
- (+) Qualquer pessoa, e o CI, consegue compilar o app sem editar arquivos na cache do Dart.
- (+) O APK de release passa a ser gerado automaticamente a cada alteração.
- (-) A manutenção desse plugin passa a ser responsabilidade do projeto.
- (-) Uma troca futura por um plugin mantido continua possível e contida: o Bluetooth está isolado
  atrás de `ObdTransport` (ADR 0001), então só `serial_transport.dart` mudaria.
