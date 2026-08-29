# Telemetria Automotiva Avançada (Edge-to-Cloud) - Módulo Mobile

**Nome do Estudante**: Samuel Morsch
**Instituição**: Universidade Católica de Santa Catarina
**Curso**: Engenharia de Software

![Badge em Desenvolvimento](http://img.shields.io/static/v1?label=STATUS&message=FINALIZADO&color=GREEN&style=for-the-badge)
![Badge Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Badge Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Badge SQLite](https://img.shields.io/badge/SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white)
![Badge Bluetooth](https://img.shields.io/badge/Bluetooth_Serial-0082FC?style=for-the-badge&logo=bluetooth&logoColor=white)

---

## Glossário e Navegação

- [Descrição do Projeto](#descrição)
- [Arquitetura do Sistema](#arquitetura)
- [Especificação Técnica](#especificação-técnica)
- [Design e Interface (Dark HUD)](#design)
- [Instruções de Execução](#execução)
- [Próximos Passos (Ecossistema)](#ecossistema)

<a id="descrição"></a>
## Descrição

Este repositório contém o **Módulo Mobile (Edge)** do sistema de Telemetria Automotiva Avançada. Trata-se de um aplicativo desenvolvido em Flutter capaz de se comunicar com a centralina eletrônica (ECU) de veículos reais através de um scanner ELM327 via protocolo OBD-II Bluetooth.

O aplicativo atua como um scanner bidirecional de bolso, permitindo a leitura de dados do motor em tempo real, detecção automática de falhas (DTCs), armazenamento offline e a emissão de laudos técnicos em PDF.

### Motivação Acadêmica
Projeto desenvolvido como Trabalho de Conclusão de Curso (TCC), aplicando conceitos de Edge Computing, persistência de dados offline-first e arquitetura limpa (Clean Code) para democratizar e profissionalizar o diagnóstico automotivo.

### Escopo das Funcionalidades Mobile
* **Telemetria ao Vivo:** Leitura de RPM e Velocidade exibidos em Gauges interativos.
* **Diagnóstico Bidirecional:** Leitura de códigos de falha e envio de comando (04) para reset da ECU (apagar luz de injeção).
* **Persistência Offline:** Gravação inteligente de histórico de falhas utilizando SQLite para evitar redundância de dados na mesma viagem.
* **Exportação Profissional:** Geração de laudos de diagnóstico em PDF com compartilhamento nativo integrado.

<a id="arquitetura"></a>
## Arquitetura

O sistema global adota uma arquitetura polirepositório **Edge-to-Cloud**. Este aplicativo representa a ponta (Edge), responsável pela coleta primária de hardware.

*(Espaço reservado para adicionar uma imagem do seu diagrama de arquitetura C4 ou fluxo de dados no futuro)*

* **Camada de Hardware:** Scanner OBD-II ELM327.
* **Camada de Conectividade:** `flutter_bluetooth_serial` processando pacotes hexadecimais brutos.
* **Camada de Persistência:** `sqflite` atuando como memória de curto/médio prazo.
* **Camada de Apresentação:** Interface reativa baseada em `ValueNotifier` e componentes `Syncfusion`.

<a id="especificação-técnica"></a>
## Especificação Técnica e Stack

* **Front-end:** Flutter, Dart.
* **Gráficos e UI:** `syncfusion_flutter_gauges` (Instrumentação), Tema personalizado "Dark HUD".
* **Banco de Dados Local:** SQLite.
* **Processamento de Relatórios:** Bibliotecas `pdf` e `printing`.

<a id="design"></a>
## Design e Interface (Dark HUD)

A interface foi projetada utilizando os princípios de **Dark HUD (Heads-Up Display)**, padrão na indústria automotiva moderna. O fundo em tons de Slate (grafite/azul marinho) reduz o cansaço visual, economiza bateria em telas OLED e minimiza reflexos no para-brisa durante o uso noturno.

*(Adicione aqui algumas screenshots da tela principal do app e da tela de histórico no futuro)*

<a id="execução"></a>
## Instruções de Execução

### Pré-requisitos
* Flutter SDK instalado.
* Dispositivo Android físico (emuladores não suportam a conexão Bluetooth Serial necessária para o scanner).
* Scanner OBD-II ELM327 pareado previamente nas configurações Bluetooth do celular.

### Setup Local

1. **Clone o repositório:**
   ```bash
   git clone [https://github.com/seu-usuario/telemetria-app.git](https://github.com/seu-usuario/telemetria-app.git)
   cd telemetria-app
