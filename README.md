<div align="center">
  <img src="Image/mk3.png" alt="DBK TX16 MK3" width="420"/>
</div>

# DBK_TX16KMK3

Widget de telemetria para **EdgeTX** voltado ao uso com **Rotorflight** em rádios da linha **RadioMaster TX16 MK3**.

O foco deste projeto é entregar uma tela principal limpa, legível e otimizada para helicópteros, com informações de voo, estado de arm, governor, alertas sonoros e integração com as imagens do modelo no cartão SD.

## Funcionalidades

- Tela principal em layout dedicado para TX16 MK3
- Exibição em tempo real de:
  - RSSI/link quality
  - RPM
  - tensão principal
  - tensão por célula
  - tensão de BEC
  - temperatura
  - corrente
  - consumo de bateria
  - percentual de bateria
- Status de `ARM` com prioridade para `disable flags`
- Exibição do estado do `Governor`
- Contador de voos e timer de voo
- Nome do piloto usando o `OwnerID`/dados do rádio, com fallback para a configuração do widget
- Alertas sonoros para:
  - armado
  - desarmado
  - governor `OFF`
  - governor `SPOOLUP`
  - governor `ACTIVE`
  - mudança de profile
  - bateria baixa
- Alerta háptico triplo para bateria baixa
- Controle opcional dos LEDs do rádio:
  - azul quando armado
  - vermelho quando desarmado
  - animação vermelha em caso de `disable flag`
- Uso das imagens do modelo a partir da pasta `/IMAGES` do cartão SD
- Timer de voo por sessão
- Contagem de voos por modelo

## Requisitos

- Rádio compatível com **EdgeTX**
- Rotorflight com telemetria CRSF funcionando
- Cartão SD com suporte a widgets Lua

## Instalação

Copie o conteúdo deste projeto para a seguinte pasta do cartão SD:

```text
/WIDGETS/DBK_TX16KMK3/
```

Os arquivos principais do widget devem ficar assim:

```text
/WIDGETS/DBK_TX16KMK3/main.lua
/WIDGETS/DBK_TX16KMK3/audio/
/WIDGETS/DBK_TX16KMK3/Image/
```

Depois no rádio:

1. Abra a página onde deseja usar o widget.
2. Escolha um layout com suporte a widget em tela cheia.
3. Selecione o widget `DBK_TX16KMK3`.
4. Ajuste as opções conforme necessário.

## Imagens dos modelos

As imagens dos modelos agora são carregadas da pasta:

```text
/IMAGES/
```

O nome do arquivo deve corresponder ao nome do modelo no rádio, normalmente **sem o primeiro caractere `>`** quando ele existir.

Exemplo:

- Nome do modelo no rádio: `>GOOSKYRS4`
- Arquivo da imagem: `/IMAGES/GOOSKYRS4.png`

Se a imagem do modelo não for encontrada, o widget usa a imagem padrão interna.

## Configuração do widget

O widget possui as seguintes opções:

- `SquareColor`: cor dos textos e elementos secundários
- `ValueColor`: cor dos valores principais
- `DispLED`: habilita ou desabilita os LEDs do rádio
- `HoldSwitch`: chave usada para congelar mínimos e máximos
- `UserName`: nome de fallback caso o rádio não forneça `OwnerID`
- `BatAlertPct`: percentual de bateria para disparo do alerta de bateria baixa

O valor padrão inicial para `BatAlertPct` é `25`.

## Telemetria esperada

O widget foi preparado para trabalhar com sensores Rotorflight/CRSF como:

- `Vbat`
- `Curr`
- `Hspd`
- `Capa`
- `Bat%`
- `Tesc`
- `1RSS`
- `RQly`
- `Thr`
- `Vbec`
- `ARM`
- `Gov`
- `Vcel`
- `PID#`
- `ARMD`

Uma forma simples de habilitar todos os sensores necessários é executar este comando no CLI:

```text
set telemetry_sensors = 3,4,5,6,7,8,43,50,60,88,90,91,99,95,96,15,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
```

## Alertas e comportamento

### Timer de voo

O campo `Time` mostra o tempo do voo atual.

- o timer começa a contar quando o modelo entra em estado armado
- o timer para quando o modelo é desarmado
- ele representa o tempo da sessão de voo atual, não um acumulado total do rádio

Isso permite usar o timer como referência rápida do voo em andamento, especialmente para gerenciamento de bateria.

### Contagem de voos por modelo

O campo `Flight` mostra dois contadores:

- o valor da esquerda representa o total acumulado de voos daquele modelo no rádio
- o valor da direita representa a quantidade de voos registrada para o modelo no contexto atual exibido pelo widget

Na prática, a contagem é feita por modelo, então cada aeronave mantém seu próprio histórico separado.

Um novo voo só é contabilizado quando há um ciclo válido de voo, evitando contagens indevidas em arm/desarm muito curtos.

### ARM e disable flags

- Quando houver `disable flags`, o texto de bloqueio tem prioridade sobre `ARMED`
- O campo usa a mesma área visual do status de arm
- `disable flags` aparecem em vermelho
- `ARMED` aparece em amarelo

### Governor

O estado do governor pode ser obtido:

- diretamente do sensor `Gov`, quando disponível
- ou inferido a partir do throttle, seguindo a lógica já usada no RFMONO

### Bateria baixa

Quando a bateria atinge o percentual configurado:

- o widget toca o áudio de alerta
- dispara 3 pulsos de haptic

## Observações

- Este projeto é voltado para **EdgeTX**, não Ethos
- A pasta `.vscode/` não faz parte da instalação no rádio
- A pasta `modelImage/` deixou de ser a origem principal das imagens dos modelos

## Versão

Versão atual do widget: **v1.0.1**
