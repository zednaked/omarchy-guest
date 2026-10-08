import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar side of the board: a small mark that lights up when a document
// changed since you last opened it.
//
// This is the whole point of splitting the plugin in two. Something written to
// the board should not shove a window in front of you - it should sit in the
// bar and wait. The heavy half (parsing, physics, the overlay) stays asleep
// until you click.
Panel {
  id: root

  moduleName: "zed.quadro"
  ipcTarget: "zed.quadro.widget"

  readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alerting: Board.hasNew

  readonly property int barSlot: Style.bar.iconFont + Style.space(12)
  readonly property real openPanelIndicatorWidth: Style.bar.iconFont
  readonly property real openPanelIndicatorHeight: Style.bar.iconFont
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    opticalSize: Style.bar.iconFont
    tooltipText: Board.count === 0
      ? "Quadro vazio"
      : (root.alerting
          ? "Quadro: algo novo desde a ultima vez (" + Board.count + " documentos)"
          : "Quadro · " + Board.count + " documentos")

    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          // Nós ligados por uma linha: o mesmo desenho do que o quadro mostra.
          text: "󱒒"
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          renderType: Text.NativeRendering
          color: root.foreground
        }

        // O aviso é um ponto, não um número: quantos arquivos mudaram não
        // ajuda em nada, e badge com contador vira ruído que se aprende a
        // ignorar. Ou tem coisa nova, ou não tem.
        Rectangle {
          visible: root.alerting
          width: 6; height: 6; radius: 3
          color: Commons.Color.accent
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
      if (b === Qt.RightButton) Board.scan()
      else Board.open = !Board.open
    }
  }
}
