import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Vista do contador de atualizacoes. Todo o estado esta em UpdatesStore, que e
// singleton: um widget de barra e instanciado uma vez por monitor, e tres
// timers consultando a mesma coisa seria desperdicio e ruido de rede.
Panel {
  id: root

  moduleName: "zed.updates"
  ipcTarget: "zed.updates"

  // `barForeground`, e nao `foreground`: sao cores diferentes, e quem os botoes
  // da barra usam (Ui/WidgetButton.qml:11) e a primeira. Peguei a segunda na
  // primeira versao e o icone saiu oliva ao lado de vizinhos laranjas, lendo
  // como desabilitado.
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int total: UpdatesStore.total
  readonly property bool temAtualizacao: total > 0

  // Largura do balao com o numero, e da linha icone+balao. Calculada aqui e
  // nao dentro do iconComponent: aquele Component tem escopo proprio e os ids
  // declarados la nao se enxergam daqui.
  readonly property int badgeWidth: temAtualizacao
    ? Math.max(Style.space(12), String(total).length * Style.space(6) + Style.space(8))
    : 0
  readonly property int barContentWidth:
    Style.bar.iconFont + badgeWidth + (badgeWidth > 0 ? Style.space(5) : 0)

  // Panel e um Item sem tamanho proprio: sem isto a barra entrega largura zero
  // ao widget, o conteudo ainda pinta e o botao para de ser clicavel.
  readonly property int barSlot: barContentWidth + Style.space(10)
  readonly property real openPanelIndicatorWidth: barContentWidth
  readonly property real openPanelIndicatorHeight: barContentWidth
  implicitWidth: bar && bar.vertical ? (bar ? bar.barSize : Style.bar.sizeHorizontal) : barSlot
  implicitHeight: bar && bar.vertical ? barSlot : (bar ? bar.barSize : Style.bar.sizeHorizontal)

  // Ajustes por entrada da barra no shell.json. Aplicado tambem em
  // settingsChanged, e nao so no onCompleted: o host atribui `settings` depois
  // de construir o widget, entao ler so na conclusao pega o objeto vazio.
  function applySettings() {
    var minutos = Number(root.setting("intervalMinutes", 30))
    if (minutos > 0)
      UpdatesStore.intervalMinutes = minutos
  }

  onSettingsChanged: root.applySettings()
  Component.onCompleted: root.applySettings()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: root.barSlot
    // O iconComponent e carregado num quadrado de opticalSize, pensado para um
    // glifo so. Alargar tambem, senao o icone cai fora e sobra so o balao.
    opticalSize: root.barContentWidth
    tooltipText: UpdatesStore.tooltip

    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            // Caixa de pacote. O mesmo glifo que o HyDE usa na waybar dele.
            text: "󰏔"
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
            // Sempre `foreground`: o icone acompanha os vizinhos, e quem chama
            // atencao e o balao com o numero.
            color: button.foreground
            opacity: UpdatesStore.checking ? 0.5 : 1.0

            Behavior on opacity {
              NumberAnimation { duration: 200 }
            }
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.temAtualizacao
            height: Style.space(12)
            width: root.badgeWidth
            radius: height / 2
            color: button.foreground

            Text {
              anchors.centerIn: parent
              text: root.total
              textFormat: Text.PlainText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              renderType: Text.NativeRendering
              color: Color.background
            }
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton)
        UpdatesStore.refresh()
      else
        UpdatesStore.openUpdater()
    }
  }
}
