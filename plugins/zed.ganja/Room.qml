import QtQuick
import Quickshell
import qs.Commons
import "Art.js" as Art
import "Palette.js" as Palette

// O conteudo da growing room, sem a janela em volta.
//
// Existe separado porque o overlay pode aparecer de duas formas: como camada
// sobre a tela (o PanelWindow do layer-shell, em cheio/grande/medio/pequeno) ou
// como janela de verdade, que o Hyprland arruma junto com as outras. O que se
// ve por dentro e o mesmo nos dois casos, e duplicar isso seria garantir que
// um dos dois ficaria para tras na proxima mudanca.
//
// `ui` e o Ganja.qml: dele vem o quadro da animacao, a paleta, o estado da
// aba e as funcoes derivadas. `active` diz se este exemplar e o que esta na
// tela - com dois monitores existem dois, e so um deve pedir repintura.
Item {
  id: room

  required property var ui
  property bool active: true

  // `framed` e a diferenca visual entre os modos: em cheio a sala e a tela
  // inteira e nao precisa de moldura; nos outros ela e um cartao sobre o que
  // estava ali antes, e um cartao sem borda nao se le como cartao.
  property bool framed: false

  // Em tamanho pequeno nao cabe tudo. O que sai primeiro e o painel do strain
  // (que e leitura, nao acompanhamento), depois as linhas de medidor que menos
  // mudam. A planta nunca sai: e ela o motivo da janela existir.
  readonly property bool wide: room.width >= 900
  // `roomy` e mais alto que `wide` porque a linha de atalhos inteira tem cento
  // e cinquenta caracteres: cabia no painel do strain e nao cabia nela mesma, e
  // no modo medio ela entrava por baixo da assinatura do rodape.
  readonly property bool roomy: room.width >= 1180
  readonly property bool tall: room.height >= 560
  readonly property bool veryTall: room.height >= 640
  readonly property int pad: room.width >= 900 ? 26 : 16
  // ---- medidor -------------------------------------------------------------
  // O Gauge do ratatui: um bloco com titulo na borda, a barra preenchida ate a
  // porcentagem e o rotulo centralizado por cima.
  component Meter: Item {
    id: meter
    property string title: ""
    property real value: 0          // 0-100
    property string label: ""
    property color fill: "#888888"
    implicitHeight: 44

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: room.ui.rule
      radius: 2
    }

    Rectangle {
      anchors { left: parent.left; top: parent.top; leftMargin: 9; topMargin: -1 }
      width: titleText.implicitWidth + 8
      height: 2
      color: "#0b0d0b"
    }
    Text {
      id: titleText
      anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.top }
      text: meter.title
      color: room.ui.inkDim
      font.family: room.ui.mono
      font.pixelSize: 11
    }

    Item {
      anchors { fill: parent; margins: 9; topMargin: 14 }

      Rectangle {
        anchors.fill: parent
        radius: 2
        color: Qt.rgba(1, 1, 1, 0.05)
      }
      Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: parent.width * Math.min(Math.max(meter.value, 0), 100) / 100
        radius: 2
        color: meter.fill
        opacity: 0.85
        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutQuad } }
      }
      // O rotulo fica centralizado na pista inteira e troca de cor onde a barra
      // passa por baixo dele, como o Gauge do ratatui faz com a inversao de
      // atributo. Uma cor so nao serve: clara some no cheio, escura some no
      // vazio, e o valor fica ilegivel exatamente na metade das vezes.
      Item {
        id: track
        anchors.fill: parent
        readonly property real fillW: parent.width * Math.min(Math.max(meter.value, 0), 100) / 100

        Item {
          width: track.fillW
          height: track.height
          clip: true
          Text {
            x: (track.width - implicitWidth) / 2
            y: (track.height - implicitHeight) / 2
            text: meter.label
            color: "#0b0d0b"
            font.family: room.ui.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }
        Item {
          x: track.fillW
          width: track.width - track.fillW
          height: track.height
          clip: true
          Text {
            x: (track.width - implicitWidth) / 2 - parent.x
            y: (track.height - implicitHeight) / 2
            text: meter.label
            color: room.ui.ink
            font.family: room.ui.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
          }
        }
      }
    }
  }

  component Section: Item {
    id: sec
    property string title: ""
    default property alias content: inner.data

    // A altura sai do conteudo, e o conteudo mora num Item - que NAO calcula
    // tamanho implicito a partir dos filhos. `inner.implicitHeight` era zero, a
    // moldura fechava logo abaixo do titulo e o texto inteiro caia para fora
    // dela, ainda por cima cortado embaixo pelo clip do Flickable. Quem sabe o
    // tamanho real do que esta la dentro e `childrenRect`.
    implicitHeight: inner.height + 30

    Rectangle {
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: room.ui.rule
      radius: 2
    }
    Rectangle {
      anchors { left: parent.left; top: parent.top; leftMargin: 9; topMargin: -1 }
      width: secTitle.implicitWidth + 8
      height: 2
      color: "#0b0d0b"
    }
    Text {
      id: secTitle
      anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.top }
      text: sec.title
      color: room.ui.inkDim
      font.family: room.ui.mono
      font.pixelSize: 11
    }
    Item {
      id: inner
      // Sem `fill`: a altura precisa vir de baixo para cima, do conteudo para a
      // moldura. Ancorar no fundo faria o contrario e fecharia o laco.
      anchors {
        left: parent.left; right: parent.right; top: parent.top
        leftMargin: 14; rightMargin: 14; topMargin: 16
      }
      height: childrenRect.height
    }
  }

  clip: room.framed

  // O fundo da sala. Em cheio e a tela; nos outros modos e um cartao, e o
  // arredondamento com a borda e o que faz o olho ler "janela" em vez de
  // "pedaco de tela escurecido".
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.043, 0.051, 0.043, room.framed ? 0.995 : 0.99)
    radius: room.framed ? 10 : 0
    border.width: room.framed ? 1 : 0
    border.color: room.ui.rule
  }

  // ---- cabecalho ----
  Text {
    id: header
    anchors { top: parent.top; left: parent.left; topMargin: room.pad; leftMargin: room.pad + 4 }
    text: {
      var d = Art.borderDecoration(room.ui.frame)
      var speed = (room.ui.frame % 4 < 2) ? ">" : "<"
      var head = d + " GANJA  ·  dia " + Grow.day + "  ·  " + Grow.stageLabel
      if (room.wide) head += "  ·  " + Palette.modeName(Grow.visualMode)
      head += "  " + d + " " + speed
      if (Grow.autoCare) head += "   AUTO"
      if (Grow.turbo) head += "   ·· TURBO 130000x ··"
      else if (Grow.fast) head += "   ·· demonstracao 130000x ··"
      return head
    }
    // Duas cores para dois riscos: a demonstracao e ambar porque nada do que
    // ela faz conta, o turbo e vermelho porque tudo conta.
    color: Grow.turbo ? "#ff7b6e" : (Grow.fast ? "#ffd166" : room.ui.inkBright)
    font.family: room.ui.mono
    font.pixelSize: 13
    font.weight: Font.DemiBold
  }

  Text {
    anchors { top: header.top; right: parent.right; rightMargin: room.pad + 4 }
    visible: room.width >= 620
    // O cabecalho ja escreve "·· TURBO 130000x ··" e "·· demonstracao ··".
    // Repetir a palavra aqui gastava a unica linha que tem espaco para dizer o
    // que ela SIGNIFICA - que e a diferenca entre os dois modos e a unica coisa
    // que o jogador precisa saber quando olha para ca.
    text: room.ui.status !== "" ? room.ui.status
        : Grow.turbo ? "isto esta acontecendo de verdade"
        : Grow.fast ? "nada disto conta"
        : (Grow.ready ? "pronta para colher · h"
          : Grow.autoCare ? "automatico · a planta se cuida" : Grow.strainName)
    color: room.ui.status !== "" ? room.ui.inkBright
         : (Grow.ready ? "#ffd166" : room.ui.inkDim)
    font.family: room.ui.mono
    font.pixelSize: 12
  }

  Rectangle {
    id: topRule
    anchors { top: header.bottom; left: parent.left; right: parent.right; topMargin: 14 }
    height: 1
    color: room.ui.rule
  }

  // ---- corpo ----
  Item {
    id: body
    anchors {
      top: topRule.bottom; bottom: footer.top
      left: parent.left; right: parent.right
      margins: room.pad - 6
    }
    visible: !room.ui.showHarvests

    // coluna da direita: o strain
    Flickable {
      id: strainPane
      anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
      visible: room.wide
      width: room.wide ? Math.min(340, parent.width * 0.3) : 0
      contentWidth: width
      contentHeight: strainInfo.implicitHeight + 16
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Section {
        id: strainInfo
        y: 8                      // espaco para o rotulo, que sobe acima da borda
        width: strainPane.width
        title: "[ strain ]"

        Column {
          width: parent.width
          spacing: 7

          Text {
            text: Grow.strainName
            color: "#7fd6e0"
            font.family: room.ui.mono
            font.pixelSize: 15
            font.weight: Font.DemiBold
          }
          Text {
            text: room.ui.strainField("type")
            color: "#e0c24a"
            font.family: room.ui.mono
            font.pixelSize: 12
          }
          Item { width: 1; height: 4 }

          Repeater {
            model: room.ui.strainRows
            delegate: Column {
              required property var modelData
              width: strainInfo.width - 28
              spacing: 2
              Text {
                text: modelData.label
                color: "#6fbf73"
                font.family: room.ui.mono
                font.pixelSize: 11
                font.weight: Font.DemiBold
              }
              Text {
                width: parent.width
                text: modelData.value
                color: room.ui.ink
                wrapMode: Text.WordWrap
                font.family: room.ui.mono
                font.pixelSize: 12
              }
              Item { width: 1; height: 5 }
            }
          }
        }
      }
    }

    // coluna da esquerda: planta e medidores
    Item {
      id: leftPane
      anchors {
        top: parent.top; bottom: parent.bottom
        left: parent.left
        right: room.wide ? strainPane.left : parent.right
        rightMargin: room.wide ? 18 : 0
      }

      // ---- a planta ----
      Rectangle {
        id: plantBox
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: meters.top; bottomMargin: 14 }
        color: Palette.hex(Palette.backgroundTint(Grow.visualMode, Grow.stage))
        border.width: 1
        border.color: room.ui.rule
        radius: 2
        // Sem `clip` aqui: o rotulo do bloco fica metade acima da borda
        // de cima, como no ratatui, e um clip na caixa corta a metade de
        // cima de "[ planta ]". Quem recorta e o Item de dentro.

        Rectangle {
          anchors { left: parent.left; top: parent.top; leftMargin: 9; topMargin: -1 }
          width: plantTitle.implicitWidth + 8; height: 2
          color: plantBox.color
        }
        Text {
          id: plantTitle
          anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.top }
          text: "[ planta ]"
          color: room.ui.inkDim
          font.family: room.ui.mono
          font.pixelSize: 11
        }

        // ---- a grade de 70x28 ----
        //
        // Duas regras, e as duas foram aprendidas apanhando:
        //
        // 1. Quem mede e o proprio contexto do canvas. `FontMetrics`,
        //    com a MESMA familia e o MESMO pixelSize, devolve outro
        //    numero: nesta maquina, para "monospace" a 9 px, a
        //    FontMetrics diz 11,16 de avanco e o canvas desenha 5,40 -
        //    a mesma fonte resolvida por dois caminhos diferentes.
        //    Posicionar por um e desenhar pelo outro faz a arte abrir
        //    como um leque: a linha de terra encolhe para metade da
        //    largura enquanto o tronco fica na coluna certa, longe dela.
        //    `ctx.measureText` e a unica medida que descreve o que vai
        //    aparecer na tela.
        //
        // 2. Cada caractere e desenhado na SUA celula, nao em blocos de
        //    mesma cor. Desenhar a corrida inteira deixa o espacamento
        //    por conta do avanco da fonte, e qualquer diferenca acumula
        //    ao longo da linha - trinta e oito tils saem 5% mais
        //    estreitos e a planta desalinha da terra. Custa algumas
        //    centenas de fillText por quadro, quase todos pulados por
        //    serem espaco, e em troca a grade fecha por construcao,
        //    mesmo que a fonte caia num fallback proporcional.
        Item {
          id: plantClip
          anchors { fill: parent; margins: 1 }
          clip: true

          Canvas {
            id: plantCanvas
            anchors.fill: parent
            renderStrategy: Canvas.Cooperative
            renderTarget: Canvas.Image

            // Proporcao do avanco, medida uma vez pelo proprio canvas
            // num tamanho de referencia. 0,6 e o palpite inicial, valido
            // para qualquer monoespacada, e sobrevive so ate o primeiro
            // quadro.
            property real advRatio: 0.6
            readonly property real lineRatio: 1.34

            readonly property int cellPx: Math.max(7, Math.min(40,
              Math.floor(Math.min((width - 24) / 70 / advRatio,
                                  (height - 22) / 28 / lineRatio))))

            function fontAt(px) { return px + "px \"" + room.ui.mono + "\"" }

            Connections {
              target: root
              function onFrameChanged() { if (room.active) plantCanvas.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onCellPxChanged: requestPaint()

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()

              ctx.font = fontAt(100)
              var measured = ctx.measureText("MMMMMMMMMM").width / 1000
              if (measured > 0.2 && Math.abs(measured - advRatio) > 0.002) {
                advRatio = measured        // muda cellPx e repinta
                return
              }

              ctx.font = fontAt(cellPx)
              var cw = ctx.measureText("MMMMMMMMMM").width / 10
              if (cw <= 0) return
              var lh = cellPx * lineRatio

              var ox = Math.round((width - cw * 70) / 2)
              var oy = Math.round(height - lh * 28) - 6
              var base = lh * 0.78

              ctx.textBaseline = "alphabetic"
              ctx.textAlign = "left"

              var lines = Art.plantAscii(Grow.stage, Grow.day, room.ui.seedLimbs, room.ui.frame)
              var colors = room.ui.paletteColors(room.ui.frame)
              var last = null

              for (var r = 0; r < 28; r++) {
                var line = lines[r]
                var y = oy + r * lh + base
                for (var c = 0; c < 70; c++) {
                  var ch = line.charAt(c)
                  if (ch === " ") continue
                  var col = Palette.charColor(ch, Grow.stage, colors)
                  if (col === null) continue
                  if (col !== last) { ctx.fillStyle = Palette.hex(col); last = col }
                  ctx.fillText(ch, ox + c * cw, y)
                }
              }
            }
          }
        }
      }

      // ---- medidores ----
      Column {
        id: meters
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        spacing: 10

        Row {
          width: parent.width
          spacing: 10
          readonly property real cell: (width - 20) / 3

          Meter {
            width: parent.cell
            title: "agua" + Art.waterDrops(room.ui.frame)
            value: Grow.water
            label: Math.round(Grow.water) + "%"
            fill: room.ui.waterColor
          }
          Meter {
            width: parent.cell
            title: "npk" + Art.nutrientSparkles(room.ui.frame)
            value: Grow.nutrients
            label: Math.round(Grow.nutrients) + "%"
            fill: room.ui.npkColor
          }
          Meter {
            width: parent.cell
            title: "→ " + room.ui.nextStage.name
            value: room.ui.nextStage.percent
            label: room.ui.nextStage.left
            fill: Palette.hex(Palette.ANSI.gaugeCyan)
          }
        }

        // A segunda fileira sai quando falta altura: temperatura, umidade e
        // raiz/copa mudam devagar, e numa janela pequena o que tem que caber e
        // a planta.
        Row {
          visible: room.tall
          height: visible ? implicitHeight : 0
          width: parent.width
          spacing: 10
          readonly property real cell: (width - 20) / 3

          Meter {
            width: parent.cell
            title: "temperatura"
            value: Math.min(Math.max((Grow.temperature - 20) / 8 * 100, 0), 100)
            label: Grow.temperature.toFixed(1) + "°C"
            fill: Palette.hex(Grow.temperature >= 20 && Grow.temperature <= 28
              ? Palette.ANSI.gaugeGreen : Palette.ANSI.gaugeYellow)
          }
          Meter {
            width: parent.cell
            title: "umidade"
            value: Grow.humidity
            label: Math.round(Grow.humidity) + "%"
            fill: Palette.hex(Grow.humidity >= 50 && Grow.humidity <= 70
              ? Palette.ANSI.gaugeCyan
              : (Grow.humidity >= 40 && Grow.humidity <= 80 ? Palette.ANSI.gaugeYellow : Palette.ANSI.gaugeRed))
          }
          Meter {
            width: parent.cell
            title: "raiz / copa"
            value: (Grow.rootDevelopment + Grow.canopyDensity) / 2
            label: "R" + Math.round(Grow.rootDevelopment) + " / C" + Math.round(Grow.canopyDensity)
            fill: Palette.hex(Grow.rootDevelopment >= 60 ? Palette.ANSI.gaugeGreen
              : (Grow.rootDevelopment >= 30 ? Palette.ANSI.gaugeYellow : Palette.ANSI.gaugeRed))
          }
        }

        Meter {
          visible: room.veryTall
          height: visible ? implicitHeight : 0
          width: parent.width
          title: "saude"
          value: room.ui.healthGauge.percent
          label: room.ui.healthGauge.label
          fill: room.ui.healthGauge.color
        }
      }
    }
  }

  // ---- aba de colheitas ----
  Flickable {
    id: harvestPane
    anchors {
      top: topRule.bottom; bottom: footer.top
      left: parent.left; right: parent.right
      margins: room.pad - 6
    }
    visible: room.ui.showHarvests
    contentWidth: width
    contentHeight: harvestCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: harvestCol
      width: Math.min(parent.width, 900)
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14

      Text {
        text: Grow.totalHarvests === 0
          ? "nenhuma colheita ainda"
          : Grow.totalHarvests + (Grow.totalHarvests === 1 ? " colheita" : " colheitas")
            + "  ·  " + room.ui.totals.weight.toFixed(1) + " g no total"
            + "  ·  qualidade media " + Math.round(room.ui.totals.quality) + "%"
            + "  ·  THC " + room.ui.totals.thc.toFixed(1) + "%  CBD " + room.ui.totals.cbd.toFixed(1) + "%"
        color: room.ui.inkBright
        font.family: room.ui.mono
        font.pixelSize: 13
      }

      Text {
        visible: Grow.totalHarvests === 0
        width: parent.width
        text: "A planta colhe sozinha dez dias depois de ficar pronta, e replanta na hora.\n"
            + "O que fica e esta lista: strain, dia, peso, qualidade e quantos sustos a planta levou.\n\n"
            + "E o que separa uma planta bonita de uma coisa que acumula - a decima colheita\n"
            + "tem dez historias atras dela."
        color: room.ui.inkDim
        wrapMode: Text.WordWrap
        font.family: room.ui.mono
        font.pixelSize: 12
        lineHeight: 1.5
        lineHeightMode: Text.ProportionalHeight
      }

      Repeater {
        model: room.ui.harvestRows
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: harvestCol.width
          height: 58
          color: index % 2 === 0 ? Qt.rgba(1, 1, 1, 0.025) : "transparent"
          radius: 2

          Row {
            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
            spacing: 16

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 44
              horizontalAlignment: Text.AlignRight
              text: "#" + modelData.n
              color: room.ui.inkDim
              font.family: room.ui.mono
              font.pixelSize: 12
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: 230
              spacing: 3
              Text {
                text: modelData.strain_name
                color: "#7fd6e0"
                font.family: room.ui.mono
                font.pixelSize: 13
                font.weight: Font.DemiBold
              }
              Text {
                text: "dia " + modelData.harvest_day + "  ·  " + modelData.when
                color: room.ui.inkDim
                font.family: room.ui.mono
                font.pixelSize: 11
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 96
              text: modelData.weight_grams.toFixed(1) + " g"
              color: "#6fbf73"
              font.family: room.ui.mono
              font.pixelSize: 13
              font.weight: Font.DemiBold
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 110
              text: Math.round(modelData.quality_score) + "% qualidade"
              color: modelData.quality_score >= 90 ? "#6fbf73"
                   : (modelData.quality_score >= 75 ? "#e0c24a" : "#e05a4f")
              font.family: room.ui.mono
              font.pixelSize: 12
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: 150
              text: "THC " + modelData.thc_percent.toFixed(1) + "%  CBD " + modelData.cbd_percent.toFixed(1) + "%"
              color: room.ui.ink
              font.family: room.ui.mono
              font.pixelSize: 12
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.stress_events === undefined ? ""
                : (modelData.stress_events === 0 ? "sem sustos"
                  : modelData.stress_events + (modelData.stress_events === 1 ? " susto" : " sustos"))
              color: modelData.stress_events ? "#e0c24a" : room.ui.inkDim
              font.family: room.ui.mono
              font.pixelSize: 11
            }
          }
        }
      }
    }
  }

  // ---- rodape ----
  //
  // Duas linhas, e nao duas pontas da mesma linha. Os atalhos ancorados a
  // esquerda e o credito ancorado a direita dividiam a MESMA faixa de 44 px:
  // na largura em que a linha de atalhos "roomy" quase preenche o rodape, os
  // dois se encontravam no meio e liam um por cima do outro. Ancora oposta nao
  // e layout - nada ali sabia da largura do vizinho.
  //
  // Agora o credito tem faixa propria em cima, e o rodape so cresce quando ele
  // aparece: sem credito a altura continua sendo os 44 px de antes.
  Item {
    id: footer
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    height: credito.visible ? 62 : 44

    Rectangle {
      anchors { left: parent.left; right: parent.right; top: parent.top }
      height: 1
      color: room.ui.rule
    }

    Text {
      // Presa embaixo, e nao no centro do rodape: quando o credito aparece a
      // faixa cresce para cima, e os atalhos nao se mexem.
      anchors { left: parent.left; bottom: parent.bottom; bottomMargin: 15; leftMargin: room.pad + 4 }
      // O rodape encolhe junto com a janela: uma linha de atalhos cortada no
      // meio nao ensina nada, so ocupa a altura que a planta queria.
      text: room.ui.showHarvests
        ? "tab volta para a planta  ·  esc fecha"
        : room.roomy
          ? "w rega  ·  n alimenta  ·  a automatico  ·  h colhe  ·  v cores  ·  t tamanho  ·  f demonstracao  ·  shift+f TURBO  ·  tab colheitas  ·  r rele o save  ·  esc fecha"
          : "w rega · n alimenta · a auto · v cores · t tamanho · f demo · shift+f turbo · tab · esc"
      color: room.ui.inkDim
      font.family: room.ui.mono
      font.pixelSize: 11
    }

    Text {
      id: credito
      anchors { top: parent.top; right: parent.right; topMargin: 7; rightMargin: room.pad + 4 }
      // Sempre presente. Ele sumia abaixo de `roomy` (1180 px), e aquele limiar
      // nao era sobre ele: era para nao entrar por baixo da linha de atalhos,
      // problema que a faixa propria resolveu. Com faixa so dele, o unico que
      // disputa espaco e a largura da janela - e para isso o texto ENCOLHE, que
      // e o que a linha de atalhos aqui do lado ja faz.
      //
      // Os cortes sao a largura livre, nao a da janela: a 10 px o mono anda ~6
      // px por caractere, entao a forma inteira (48 caracteres) pede ~290 px e a
      // media (16) pede ~100. Com folga, 320 e 140.
      readonly property int livre: room.width - 2 * (room.pad + 4)
      text: livre >= 320 ? "Ganja-TUI de ZeD, portado para o shell do Omarchy"
          : livre >= 140 ? "Ganja-TUI de ZeD"
          : "ZeD"
      color: room.ui.rule
      font.family: room.ui.mono
      font.pixelSize: 10
    }
  }
}
