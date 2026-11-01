# flutter_bluetooth_serial 0.4.0 (cópia mantida neste repositório)

**Origem:** pacote `flutter_bluetooth_serial` 0.4.0 publicado em pub.dev
(https://github.com/edufolly/flutter_bluetooth_serial), licença MIT (arquivo `LICENSE`).

## Por que existe esta cópia

O pacote está sem manutenção desde 2021. Sua configuração Android original usa `jcenter()`,
repositório desativado e removido no Gradle 9, e não declara `namespace`. Com Gradle 9.1 e
Android Gradle Plugin 9 (usados por este app), o build falha em qualquer máquina que baixe o
pacote original, inclusive no CI. Manter a cópia corrigida aqui torna o build reproduzível:
quem clonar o repositório não precisa editar arquivos na cache do Dart.

## O que foi alterado

| Arquivo | Alteração |
|---|---|
| `android/build.gradle` | `jcenter()` -> `mavenCentral()`; Kotlin 1.8.0; AGP 7.4.2 no `classpath`; `namespace` e `compileSdkVersion 34` |
| `pubspec.yaml` | limite superior do Dart de `<3.0.0` para `<4.0.0` |
| `example/` | removida (exemplo do autor, não utilizado) |

O código Dart (`lib/`) e Java (`android/src/`) **não foi modificado**.

## Como é usado

`pubspec.yaml` do app:

```yaml
flutter_bluetooth_serial:
  path: third_party/flutter_bluetooth_serial
```

O acesso ao Bluetooth fica isolado no app atrás de `ObdTransport`
(ver `docs/adr/0001-app-nucleo-testavel-fila-local-e-bluetooth-isolado.md`), o que permite
trocar este plugin por outro mantido sem alterar o núcleo OBD-II.
