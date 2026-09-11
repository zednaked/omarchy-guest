import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Art.js" as Art
import "Palette.js" as Palette

// A growing room: a planta ao centro, os medidores embaixo, o strain a direita.
//
// Esta metade dorme. Fechada, nada aqui desenha, mede ou anima - o Timer de
// animacao so corre enquanto a janela esta visivel, e o estado inteiro mora em
// Grow.qml, que custa um timer de sessenta segundos.
//
// A paleta daqui e a do Ganja-TUI, com os RGB literais de src/ui/colors.rs, e
// nao a do tema do Omarchy. A regra e a mesma que rege o icone da barra, so que
// ao contrario: uma planta repintada com o accent do tema deixa de ser a
// planta. O tema manda na barra; aqui manda o Ganja.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: Grow.open

  // A fonte do shell, nao uma familia escolhida aqui. A primeira versao do
  // zed.quadro nomeou "IBM Plex Mono", a maquina nao tinha, tudo caiu para o
  // fallback em silencio, e a tipografia que eu achava ter escolhido nunca
  // aconteceu. Tem que ser monoespacada: 70x28 so fecha com avanco fixo.
  readonly property string mono: Style.fontFamily

  property int frame: 0
  property string status: ""
  property bool showHarvests: false

  // ---- configuracao vinda do manifest -------------------------------------
  // O singleton nao recebe o manifest (o shell so injeta em quem e entrada de
  // plugin); o overlay recebe e repassa. Ele e keepLoaded, entao isto acontece
  // na carga do shell, antes do primeiro tick que importa.
  onManifestChanged: {
    if (!manifest) return
    if (typeof manifest.timeScale === "number" && manifest.timeScale > 0)
      Grow.timeScale = manifest.timeScale
    if (typeof manifest.careScale === "number" && manifest.careScale > 0)
      Grow.careScale = manifest.careScale
    if (typeof manifest.turboScale === "number" && manifest.turboScale > 0)
      Grow.turboScale = manifest.turboScale
  }

  function flash(msg) { root.status = msg; statusTimer.restart() }
  Timer { id: statusTimer; interval: 2400; onTriggered: root.status = "" }

  // ---- animacao ------------------------------------------------------------
  // Dez quadros por segundo. As animacoes da arte sao ciclos de 2, 3, 4, 8 e 12
  // quadros e a respiracao e um seno lento: passar disso gasta GPU para mostrar
  // a mesma coisa. O TUI roda a 20 - la o mesmo timer tambem le o teclado.
  Timer {
    running: root.opened
    interval: 100
    repeat: true
    onTriggered: {
      root.frame++
      if (Grow.fast) Grow.fastStep(0.1)
    }
  }

  onOpenedChanged: {
    if (root.opened) {
      root.showHarvests = false
      Grow.reread()          // outra sessao pode ter escrito; quem vai olhar pergunta
      Grow.publish()
    } else {
      // Fechar desliga os dois ritmos rapidos. O turbo queima um ciclo por
      // minuto: deixa-lo correr atras de uma janela fechada seria perder a
      // planta sem ver.
      Grow.stopFast()
      if (Grow.turbo) Grow.toggleTurbo()
    }
  }

  // ---- cores do quadro atual ----------------------------------------------

  readonly property var seedLimbs: Art.u64FromHex(Grow.seedHex)
  readonly property int flowerVariant: Art.u64ModSmall(root.seedLimbs, 6)
  readonly property int foliageVariant: Art.u64ModSmall(Art.u64DivModSmall(root.seedLimbs, 6).q, 4)
  readonly property int trunkVariant: Art.u64ModSmall(Art.u64DivModSmall(root.seedLimbs, 24).q, 3)

  function paletteColors(f) {
    var mode = Grow.visualMode
    var stage = Grow.stage
    var day = Grow.day
    var intens = Palette.flowerIntensities(stage, day)
    var breath = 0.875 + Math.sin(f * Palette.breathSpeed(mode)) * 0.125
    var hp = Palette.healthPercent(Grow.health)

    return {
      foliage: Palette.applyBreathing(Palette.foliageColor(mode, root.foliageVariant, hp, Grow.water, f), breath),
      flower1: Palette.applyBreathing(Palette.flowerColor(mode, root.flowerVariant, intens[0], stage, f), breath),
      flower2: Palette.applyBreathing(Palette.flowerColor(mode, root.flowerVariant, intens[1], stage, f), breath),
      flower3: Palette.applyBreathing(Palette.flowerColor(mode, root.flowerVariant, intens[2], stage, f), breath),
      trunk: Palette.trunkColor(mode, root.trunkVariant, day, f),
      soil: Palette.soilColor(mode, Grow.water, f)
    }
  }

  readonly property color waterColor: Palette.hex(Palette.waterColor(Grow.visualMode, Grow.water, root.frame))
  readonly property color npkColor: Palette.hex(Palette.nutrientColor(Grow.visualMode, Grow.nutrients, root.frame))

  readonly property color inkBright: "#e4e8e2"
  readonly property color ink: "#a8b0a6"
  readonly property color inkDim: "#6d756c"
  readonly property color rule: "#2a322a"

  // ---- IPC -----------------------------------------------------------------
  IpcHandler {
    target: "ganja"
    function toggle(): string { Grow.open = !Grow.open; return Grow.open ? "open" : "closed" }
    function open(): string { Grow.open = true; return "ok" }
    function close(): string { Grow.open = false; return "ok" }
    function water(): string { Grow.pour(40); return "" + Math.round(Grow.water) + "%" }
    function feed(): string { Grow.feed(40); return "" + Math.round(Grow.nutrients) + "%" }
    function harvest(): string { return Grow.harvestNow() ? "colhida" : "ainda nao esta pronta" }
    function mode(): string { Grow.cycleVisualMode(); return Grow.visualMode }
    function auto(): string { return Grow.toggleAutoCare() ? "ligado" : "desligado" }
    function turbo(): string {
      if (Grow.fast) Grow.stopFast()
      return Grow.toggleTurbo() ? "ligado · 130000x na planta" : "desligado"
    }
    function window(mode: string): string {
      if (mode === "") { root.cycleWindowMode(); return Grow.windowMode }
      if (root.windowModes.indexOf(mode) < 0)
        return "tamanhos: " + root.windowModes.join(", ")
      Grow.setWindowMode(mode)
      return Grow.windowMode
    }
    function status(): string {
      return Grow.strainName + " · " + Grow.stageLabel + " · dia " + Grow.day
        + " · agua " + Math.round(Grow.water) + "% · npk " + Math.round(Grow.nutrients) + "%"
    }
  }

  // ---- tamanho e tipo de janela -------------------------------------------
  //
  // Cinco modos, e o ultimo e de outra especie. Os quatro primeiros sao uma
  // camada do layer-shell sobre a tela: em `cheio` ela e a tela, nos outros e
  // um cartao centralizado sobre um fundo escurecido, que fecha ao clicar fora.
  // `janela` e uma janela de verdade, que o Hyprland arruma junto com as
  // outras - da para deixar a planta lado a lado com o que voce esta fazendo em
  // vez de ter que abrir e fechar.
  //
  // O modo mora no Grow e vai para o save: e uma preferencia, e preferencia que
  // volta ao padrao a cada boot nao e preferencia.
  readonly property var windowModes: ["cheio", "grande", "medio", "pequeno", "janela"]
  readonly property string windowMode: Grow.windowMode
  readonly property bool windowed: root.windowMode === "janela"

  function cycleWindowMode() {
    var i = root.windowModes.indexOf(root.windowMode)
    Grow.setWindowMode(root.windowModes[(i + 1) % root.windowModes.length])
    root.flash("janela: " + Grow.windowMode)
  }

  // Proporcao da tela, com teto absoluto. So a proporcao deixa o modo "pequeno"
  // grande demais num monitor 4K; so o absoluto o deixa maior que a tela num
  // notebook.
  function cardWidth(w) {
    switch (root.windowMode) {
    case "grande":  return Math.round(Math.min(1280, w * 0.86))
    case "medio":   return Math.round(Math.min(980, w * 0.72))
    case "pequeno": return Math.round(Math.min(720, w * 0.58))
    default:        return w
    }
  }
  function cardHeight(h) {
    switch (root.windowMode) {
    case "grande":  return Math.round(Math.min(880, h * 0.88))
    case "medio":   return Math.round(Math.min(660, h * 0.76))
    case "pequeno": return Math.round(Math.min(450, h * 0.58))
    default:        return h
    }
  }

  // ---- teclas --------------------------------------------------------------
  // Uma funcao so, chamada pelas duas janelas. Duas copias da mesma tabela de
  // teclas e a forma mais barata de fazer um atalho existir num modo e nao no
  // outro sem ninguem perceber.
  function handleKey(e) {
    switch (e.key) {
    case Qt.Key_Escape:
    case Qt.Key_Q:
      Grow.open = false; e.accepted = true; break
    case Qt.Key_W:
      Grow.pour(40); root.flash("regada · " + Math.round(Grow.water) + "%"); e.accepted = true; break
    case Qt.Key_N:
      Grow.feed(40); root.flash("alimentada · " + Math.round(Grow.nutrients) + "%"); e.accepted = true; break
    case Qt.Key_V:
      Grow.cycleVisualMode(); root.flash(Palette.modeName(Grow.visualMode)); e.accepted = true; break
    case Qt.Key_A:
      root.flash(Grow.toggleAutoCare()
        ? "automatico ligado · a planta se cuida sozinha"
        : "automatico desligado · agora e com voce")
      e.accepted = true; break
    case Qt.Key_T:
      root.cycleWindowMode(); e.accepted = true; break
    case Qt.Key_H:
      if (Grow.harvestNow()) root.flash("colhida - muda nova plantada")
      else root.flash("ainda nao esta pronta")
      e.accepted = true; break
    case Qt.Key_Tab:
      root.showHarvests = !root.showHarvests; e.accepted = true; break
    case Qt.Key_R:
      Grow.reread(); root.flash("save relido do disco"); e.accepted = true; break
    case Qt.Key_F:
      // Dois modos rapidos, e eles sao coisas diferentes de verdade - por isso
      // duas teclas em vez de uma com tres estados.
      //
      //   f        demonstracao: 130000x em cima de uma COPIA. Nada disso
      //            aconteceu; desligar devolve a planta onde ela estava.
      //   Shift+F  turbo: 130000x na planta DE VERDADE. Escreve no save, as
      //            colheitas contam, o tempo queimado nao volta.
      //
      // Os dois sao liga/desliga. Segurar a tecla, que era como a demonstracao
      // funcionava, e ruim justamente para o que ela serve: olhar.
      if (e.isAutoRepeat) { e.accepted = true; break }
      if (e.modifiers & Qt.ShiftModifier) {
        if (Grow.fast) Grow.stopFast()      // os dois ao mesmo tempo nao fazem sentido
        root.flash(Grow.toggleTurbo()
          ? "TURBO · 130000x na planta de verdade"
          : "turbo desligado · de volta ao ritmo lento")
      } else {
        if (Grow.turbo) Grow.toggleTurbo()
        if (Grow.fast) { Grow.stopFast(); root.flash("demonstracao desligada") }
        else { Grow.startFast(); root.flash("demonstracao · 130000x numa copia") }
      }
      e.accepted = true; break
    }
  }

  // ---- camada sobre a tela -------------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      // So no monitor com foco. A mesma planta desenhada em duas telas sao dois
      // canvas disputando um tamanho de area, e o segundo esta errado por
      // construcao.
      readonly property bool isTarget: {
        var f = Hyprland.focusedMonitor
        var want = f ? String(f.name || "") : ""
        if (want === "") return true
        return String(modelData.name || "") === want
      }

      visible: root.opened && isTarget && !root.windowed
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "zed-ganja"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      anchors { top: true; right: true; bottom: true; left: true }

      FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (e) { root.handleKey(e) }

        // O escurecido atras do cartao. Em cheio ele nao aparece - a sala ja
        // cobre tudo - e clicar fora nao teria "fora" nenhum para acertar.
        Rectangle {
          anchors.fill: parent
          visible: root.windowMode !== "cheio"
          color: Qt.rgba(0, 0, 0, 0.45)
          MouseArea {
            anchors.fill: parent
            onClicked: Grow.open = false
          }
        }

        Room {
          anchors.centerIn: parent
          width: root.cardWidth(parent.width)
          height: root.cardHeight(parent.height)
          ui: root
          active: win.isTarget && root.opened
          framed: root.windowMode !== "cheio"

          // Sem isto o clique na sala atravessa para o MouseArea do fundo e
          // fecha a janela que a pessoa acabou de abrir.
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        }
      }
    }
  }

  // ---- janela de verdade ---------------------------------------------------
  // Uma toplevel comum: o compositor arruma, redimensiona e fecha como faz com
  // qualquer aplicativo. E o modo para deixar a planta aberta num canto do
  // workspace em vez de abrir e fechar.
  FloatingWindow {
    id: floating
    visible: root.opened && root.windowed
    title: Grow.loaded
      ? "Ganja · " + Grow.strainName + " · dia " + Grow.day
      : "Ganja"
    color: "transparent"

    implicitWidth: 980
    implicitHeight: 660
    minimumSize: Qt.size(420, 320)

    onClosed: Grow.open = false

    FocusScope {
      anchors.fill: parent
      focus: true

      Keys.onPressed: function (e) { root.handleKey(e) }

      Room {
        anchors.fill: parent
        ui: root
        active: root.opened && root.windowed
        framed: false
      }
    }
  }


  // ---- dados derivados -----------------------------------------------------

  function strainField(key) {
    var p = Grow.viewPlant
    var s = p && p.genetics ? p.genetics.strain_info : null
    return s && s[key] !== undefined ? String(s[key]) : ""
  }

  readonly property var strainRows: {
    var p = Grow.viewPlant
    if (!p || !p.genetics) return []
    var g = p.genetics
    var s = g.strain_info
    var rows = [
      { label: "genetica", value: s ? s.genetics : "—" },
      { label: "canabinoides", value: "THC " + g.thc_percent.toFixed(1) + "%   CBD " + g.cbd_percent.toFixed(1) + "%" }
    ]
    if (s) {
      rows.push({ label: "cultivo", value: "dificuldade " + s.difficulty + "   rendimento " + s.yield_potential })
      rows.push({ label: "floracao", value: s.flowering_time + " dias   ·   porte " + s.height + "   ·   " + s.phenotype })
      rows.push({ label: "terpenos", value: s.dominant_terpenes.join(", ") })
      rows.push({ label: "aroma", value: s.aroma.join(", ") })
      rows.push({ label: "efeitos", value: s.effects.join(", ") })
    }
    rows.push({ label: "resiliencia", value: Math.round(g.resilience * 100) + "%   ·   crescimento " + g.growth_rate.toFixed(2) + "x" })
    rows.push({ label: "seed", value: Grow.seedHex })
    return rows
  }

  // Progresso ate o proximo estagio, com os mesmos limiares de growing.rs.
  readonly property var nextStage: {
    var d = Grow.day
    var target, name
    switch (Grow.stage) {
    case "Seedling": target = 11; name = "vegetativo"; break
    case "Vegetative": target = 41; name = "pre-flor"; break
    case "PreFlower": target = 49; name = "floracao"; break
    case "Flowering": target = 86; name = "colheita"; break
    case "ReadyToHarvest": return { name: "pronta", percent: 100, left: "colher" }
    default: target = 11; name = "vegetativo"
    }
    return {
      name: name,
      percent: Math.min(d / target * 100, 100),
      left: Math.max(target - d, 0) + "d"
    }
  }

  readonly property var healthGauge: {
    switch (Grow.health) {
    case "Excellent": return { percent: 100, label: "excelente ★", color: Palette.hex(Palette.ANSI.gaugeGreen) }
    case "Good": return { percent: 75, label: "boa", color: Palette.hex(Palette.ANSI.gaugeGreen) }
    case "Fair": return { percent: 50, label: "razoavel", color: Palette.hex(Palette.ANSI.gaugeYellow) }
    case "Poor": return { percent: 25, label: "ruim ⚠", color: Palette.hex(Palette.ANSI.gaugeLightRed) }
    default: return { percent: 10, label: "critica ⚠⚠", color: Palette.hex(Palette.ANSI.gaugeRed) }
    }
  }

  readonly property var harvestRows: {
    var out = []
    var h = Grow.harvests
    for (var i = h.length - 1; i >= 0; i--) {
      var r = JSON.parse(JSON.stringify(h[i]))
      r.n = i + 1 + Math.max(Grow.totalHarvests - h.length, 0)
      var d = new Date(r.completed_at)
      r.when = isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, "dd/MM HH:mm")
      out.push(r)
    }
    return out
  }

  readonly property var totals: {
    var h = Grow.harvests
    if (h.length === 0) return { weight: 0, quality: 0, thc: 0, cbd: 0 }
    var w = 0, q = 0, t = 0, c = 0
    for (var i = 0; i < h.length; i++) {
      w += h[i].weight_grams; q += h[i].quality_score
      t += h[i].thc_percent; c += h[i].cbd_percent
    }
    return { weight: w, quality: q / h.length, thc: t / h.length, cbd: c / h.length }
  }
}
