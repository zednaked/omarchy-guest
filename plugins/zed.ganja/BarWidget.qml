import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// A metade que fica acordada: um glifo por estagio e um ponto quando ha o que
// fazer.
//
// O icone e um glifo, nao a planta. A arte tem 70 colunas por 28 linhas e nao
// cabe numa barra; reduzida a tres caracteres ela deixa de ser a arte e vira
// um rabisco. Sete glifos contam a mesma historia no espaco que existe.
//
// Cor vem do tema do Omarchy, nao da paleta do Ganja. Um icone com cor propria
// no meio da barra quebra a barra - a barra e uma linha de simbolos do mesmo
// tom, e o que sai do tom le-se como erro, nao como enfase. A planta pintada
// com as cores dela esta do outro lado do clique.
Panel {
  id: root

  moduleName: "zed.ganja"
  ipcTarget: "zed.ganja.widget"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alerting: Grow.alerting

  // Um glifo por estagio. Os codigos saem da tabela de nomes do arquivo da
  // fonte que a barra usa, e nao de um catalogo na internet: os codepoints do
  // conjunto Material mudam entre versoes do Nerd Fonts, e a primeira versao
  // disto pos um logo de open source no lugar da muda e uma camera de seguranca
  // no lugar da folha - sem erro nenhum, porque o glifo existia.
  readonly property string glyph: {
    switch (Grow.stage) {
    case "Seed": return "󰹣"          // md-seed-outline
    case "Germination": return "󰹢"   // md-seed
    case "Seedling": return "󰹧"      // md-sprout-outline
    case "Vegetative": return "󰹦"    // md-sprout
    case "PreFlower": return "󰌪"     // md-leaf
    case "Flowering": return "󰞦"     // md-cannabis
    default: return "󰆐"              // md-content-cut: hora de cortar
    }
  }

  readonly property int barSlot: Style.bar.iconFont + Style.space(12)
  readonly property real openPanelIndicatorWidth: Style.bar.iconFont
  readonly property real openPanelIndicatorHeight: Style.bar.iconFont
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // O clique direito rega, e acao sem resposta visivel parece que nao
  // aconteceu. O flash e curto de proposito: e um recibo, nao uma animacao.
  property real flashAmount: 0
  SequentialAnimation {
    id: flash
    NumberAnimation { target: root; property: "flashAmount"; to: 1; duration: 90 }
    NumberAnimation { target: root; property: "flashAmount"; to: 0; duration: 420; easing.type: Easing.OutQuad }
  }

  Connections {
    target: Grow
    function onWatered() { flash.restart() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: Style.bar.iconFont
    tooltipText: !Grow.loaded
      ? "Ganja"
      : Grow.strainName + " · " + Grow.stageLabel + " · dia " + Grow.day
        + (Grow.ready ? "  ·  pronta para colher"
          : Grow.autoCare ? "  ·  automatico"
          : Grow.thirsty ? "  ·  com sede (" + Math.round(Grow.water) + "%)"
          : Grow.hungry ? "  ·  sem NPK (" + Math.round(Grow.nutrients) + "%)" : "")

    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.glyph
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          color: root.foreground
          opacity: 1 - root.flashAmount * 0.7
          scale: 1 + root.flashAmount * 0.18
        }

        // O aviso e um ponto, nao um numero. Ou tem coisa a fazer - colher,
        // regar, alimentar - ou nao tem; quanto de agua falta esta no tooltip,
        // e um badge com numero na barra vira ruido que se aprende a ignorar.
        Rectangle {
          visible: root.alerting
          width: 6; height: 6; radius: 3
          color: Color.accent
          anchors { right: parent.right; top: parent.top; rightMargin: -1; topMargin: -1 }

          SequentialAnimation on opacity {
            running: root.alerting
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.35; duration: 1400; easing.type: Easing.InOutQuad }
            NumberAnimation { from: 0.35; to: 1; duration: 1400; easing.type: Easing.InOutQuad }
          }
        }
      }
    }

    onPressed: function (b) {
      if (b === Qt.RightButton) Grow.pour(40)
      else Grow.open = !Grow.open
    }
  }
}
