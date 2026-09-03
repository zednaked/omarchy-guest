import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Quadro - a board of Markdown documents, rendered as graphs or prose.
//
// The model is deliberately thin: a folder of .md files, one tab each. There is
// no database and no way to create a document from inside the overlay, because
// the point is the other direction - an agent with shell access writes a file
// and it appears here. Same mechanic as a note left in a terminal, with a
// surface that can draw relations.
//
// Parsing lives in this file rather than in a helper script so the plugin works
// on a machine that only has the plugin. The graph format is documented in
// docs/QUADRO-FORMAT.md.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string boardDir: Quickshell.env("HOME") + "/.local/share/omarchy-guest/quadro"

  property var docs: []          // [{file, title, mode, body}]
  property int current: 0
  property string loadError: ""
  property string pendingShow: ""

  // Tamanho da area de desenho e um contador de repintura.
  //
  // O `id: canvas` vive dentro do delegate do Variants - uma instancia por
  // monitor -, e funcoes declaradas aqui no root NAO enxergam ids de dentro
  // dele. Referenciar `canvas.width` daqui lancava ReferenceError e abortava o
  // parse inteiro antes de atribuir nodes/links, o que dava um grafo vazio sem
  // nenhum erro visivel na tela.
  property real areaW: 1200
  property real areaH: 800
  property int repaintTick: 0

  // graph state for the current doc
  property var groups: ({})
  property var nodes: []
  property var links: []
  property var focusNode: null
  property var lockedNode: null
  property var draggingNode: null

  readonly property var doc: root.docs.length > 0 && root.current < root.docs.length
    ? root.docs[root.current] : null

  // ---- loading -------------------------------------------------------------
  // One process reads every file and emits a record stream. Doing it in a
  // single shell pass keeps the plugin from spawning one process per document.
  Process {
    id: reader
    command: ["sh", "-c",
      "d=\"" + root.boardDir + "\"; mkdir -p \"$d\"; " +
      "for f in \"$d\"/*.md; do [ -f \"$f\" ] || continue; " +
      "printf '\\036%s\\037' \"${f##*/}\"; cat \"$f\"; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
  }

  function reload() { if (!reader.running) reader.running = true }

  // Record separator (30) between documents, unit separator (31) between the
  // filename and its body. Escrito por codigo e nao como caractere literal: um
  // control char no fonte nao sobrevive a copiar e colar.
  function ingest(raw) {
    var parts = String(raw).split(String.fromCharCode(30))
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var chunk = parts[i]
      if (chunk.trim() === "") continue
      var cut = chunk.indexOf(String.fromCharCode(31))
      if (cut < 0) continue
      var file = chunk.substring(0, cut)
      var body = chunk.substring(cut + 1)
      out.push(root.parseDoc(file, body))
    }
    root.docs = out
    root.loadError = out.length === 0
      ? "nenhum .md em " + root.boardDir
      : ""
    if (root.current >= out.length) root.current = 0
    if (root.pendingShow !== "" && !root.applyPending()) root.buildCurrent()
    else if (root.pendingShow === "") root.buildCurrent()
  }

  // Casa por titulo, nome de arquivo, ou pedaco de qualquer um dos dois - quem
  // chama do terminal nao deveria precisar lembrar do prefixo numerico.
  function applyPending() {
    var want = root.pendingShow.toLowerCase()
    for (var i = 0; i < root.docs.length; i++) {
      var d = root.docs[i]
      if (d.title.toLowerCase().indexOf(want) >= 0 || d.file.toLowerCase().indexOf(want) >= 0) {
        root.pendingShow = ""
        root.current = i
        root.buildCurrent()
        return true
      }
    }
    root.pendingShow = ""
    return false
  }

  function parseDoc(file, body) {
    var title = file.replace(/\.md$/, "").replace(/^\d+[-_]/, "")
    var mode = ""
    var text = body

    var fm = /^---\s*\n([\s\S]*?)\n---\s*\n?/.exec(body)
    if (fm) {
      var head = fm[1].split("\n")
      for (var i = 0; i < head.length; i++) {
        var m = /^\s*(\w+)\s*:\s*(.+?)\s*$/.exec(head[i])
        if (!m) continue
        if (m[1] === "title") title = m[2]
        else if (m[1] === "mode") mode = m[2]
      }
      text = body.substring(fm[0].length)
    }
    if (mode === "") mode = /```graph\b/.test(text) ? "graph" : "prose"
    return { file: file, title: title, mode: mode, body: text }
  }

  // ---- graph parsing -------------------------------------------------------
  function buildCurrent() {
    root.focusNode = null
    root.lockedNode = null
    if (!root.doc || root.doc.mode !== "graph") {
      root.nodes = []; root.links = []; root.groups = {}
      return
    }
    var block = /```graph\s*\n([\s\S]*?)```/.exec(root.doc.body)
    var src = block ? block[1] : ""

    var groups = {}
    var nodes = []
    var byName = {}
    var pending = []   // links, resolved after every node exists
    var last = null

    var lines = src.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var trimmed = line.trim()
      if (trimmed === "" || trimmed.charAt(0) === "#") continue

      // risk line, attached to the node above it
      if (trimmed.charAt(0) === "!") {
        if (last) last.risk = trimmed.substring(1).trim()
        continue
      }

      var g = /^group\s+(\S+)\s+(#[0-9A-Fa-f]{3,8})\s*(.*)$/.exec(trimmed)
      if (g) { groups[g[1]] = { color: g[2], label: g[3] || g[1] }; continue }

      var l = /^(.+?)\s*->\s*(.+?)$/.exec(trimmed)
      if (l && trimmed.charAt(0) !== "[") { pending.push([l[1].trim(), l[2].trim()]); continue }

      var n = /^\[(\w+)\]\s*(.+)$/.exec(trimmed)
      if (n) {
        var rest = n[2].split("::")
        var node = {
          id: rest[0].trim(),
          group: n[1],
          kind: (rest[1] || "").trim(),
          note: (rest[2] || "").trim(),
          risk: "", degree: 0,
          x: 0, y: 0, vx: 0, vy: 0, r: 6
        }
        nodes.push(node); byName[node.id] = node; last = node
      }
    }

    var links = []
    for (var p = 0; p < pending.length; p++) {
      var a = byName[pending[p][0]], b = byName[pending[p][1]]
      if (a && b && a !== b) { links.push({ a: a, b: b }); a.degree++; b.degree++ }
    }

    // size from connectivity: hubs get big without anyone declaring them
    for (var k = 0; k < nodes.length; k++)
      nodes[k].r = Math.min(14, 5 + nodes[k].degree * 1.6)

    // seed positions around each group's well
    var w = root.areaW, h = root.areaH
    var wells = root.wellsFor(groups, w, h)
    for (var s = 0; s < nodes.length; s++) {
      var well = wells[nodes[s].group] || { x: w / 2, y: h / 2 }
      var ang = (s / nodes.length) * Math.PI * 2
      nodes[s].x = well.x + Math.cos(ang) * (40 + (s % 5) * 24)
      nodes[s].y = well.y + Math.sin(ang) * (40 + (s % 5) * 24)
      nodes[s].vx = 0; nodes[s].vy = 0
    }

    root.groups = groups
    root.nodes = nodes
    root.links = links
  }

  // Wells sit on a circle, so any number of groups spreads evenly instead of
  // needing hand-placed quadrants.
  function wellsFor(groups, w, h) {
    var keys = Object.keys(groups)
    var out = {}
    var cx = w / 2, cy = h / 2
    var rad = Math.min(w, h) * 0.30
    if (keys.length === 1) { out[keys[0]] = { x: cx, y: cy }; return out }
    for (var i = 0; i < keys.length; i++) {
      var a = (i / keys.length) * Math.PI * 2 - Math.PI / 2
      out[keys[i]] = { x: cx + Math.cos(a) * rad, y: cy + Math.sin(a) * rad * 0.82 }
    }
    return out
  }

  function colorOf(n) {
    var g = root.groups[n.group]
    return g ? g.color : Color.foreground
  }

  function neighborsOf(n) {
    var out = []
    for (var i = 0; i < root.links.length; i++) {
      if (root.links[i].a === n) out.push(root.links[i].b)
      else if (root.links[i].b === n) out.push(root.links[i].a)
    }
    return out
  }

  // ---- physics -------------------------------------------------------------
  Timer {
    running: root.opened && root.nodes.length > 0
    interval: 16
    repeat: true
    onTriggered: { root.step(); root.repaintTick++ }
  }

  function step() {
    var ns = root.nodes, i, j
    var w = root.areaW, h = root.areaH
    var wells = root.wellsFor(root.groups, w, h)

    for (i = 0; i < ns.length; i++) {
      var a = ns[i]
      for (j = i + 1; j < ns.length; j++) {
        var b = ns[j]
        var dx = b.x - a.x, dy = b.y - a.y
        var d2 = dx * dx + dy * dy
        if (d2 < 1) { d2 = 1; dx = Math.random() - 0.5; dy = Math.random() - 0.5 }
        var d = Math.sqrt(d2)
        var f = 3200 / d2
        var fx = (dx / d) * f, fy = (dy / d) * f
        a.vx -= fx; a.vy -= fy; b.vx += fx; b.vy += fy
      }
    }

    for (i = 0; i < root.links.length; i++) {
      var l = root.links[i]
      var lx = l.b.x - l.a.x, ly = l.b.y - l.a.y
      var ld = Math.hypot(lx, ly) || 1
      var k = 0.0015 * (ld - 115)
      l.a.vx += lx * k; l.a.vy += ly * k
      l.b.vx -= lx * k; l.b.vy -= ly * k
    }

    var t = Date.now() / 1000
    for (i = 0; i < ns.length; i++) {
      var n = ns[i]
      var well = wells[n.group]
      if (well) {
        var wx = well.x + Math.cos(t * 0.15 + well.x * 0.01) * 12
        var wy = well.y + Math.sin(t * 0.12 + well.y * 0.01) * 12
        n.vx += (wx - n.x) * 0.0030
        n.vy += (wy - n.y) * 0.0030
      }
      if (n === root.draggingNode) continue
      n.vx *= 0.86; n.vy *= 0.86
      n.x += n.vx; n.y += n.vy
      var m = n.r + 18
      n.x = Math.max(m, Math.min(w - m, n.x))
      n.y = Math.max(m, Math.min(h - m, n.y))
    }
  }

  // Sem isto o overlay nao tem como ser aberto: `opened` e so uma propriedade,
  // e quem a liga e uma chamada de IPC. Descoberto do jeito mais direto - abri
  // e nao aconteceu nada.
  //
  //   omarchy-shell quadro toggle
  //   omarchy-shell quadro open
  IpcHandler {
    target: "quadro"
    function toggle(): string { root.opened = !root.opened; return root.opened ? "open" : "closed" }
    function open(): string { root.opened = true; return "ok" }
    function close(): string { root.opened = false; return "ok" }
    function reload(): string { root.reload(); return "ok" }

    // Abrir ja na aba certa. E o que torna o quadro util para um agente: eu
    // escrevo o .md e chamo `omarchy-shell quadro show "mapa da maquina"`, em
    // vez de te pedir para procurar a aba.
    function show(name: string): string {
      // O reload roda num Process, entao os documentos ainda nao chegaram aqui.
      // Guardar o pedido e aplicar no fim do ingest e o unico jeito que nao
      // depende de sorte de temporizacao.
      root.pendingShow = name
      root.opened = true
      if (root.docs.length > 0) root.applyPending()
      root.reload()
      return "ok"
    }

    function next(): string {
      if (root.docs.length === 0) return "vazio"
      root.current = (root.current + 1) % root.docs.length
      root.buildCurrent()
      return root.docs[root.current].file
    }
  }

  onOpenedChanged: if (root.opened) root.reload()

  // The folder is watched, so a document written while the board is open shows
  // up without anyone asking for it. That is the whole point of the thing.
  Process {
    id: watcher
    running: root.opened
    command: ["sh", "-c",
      "command -v inotifywait >/dev/null || exit 0; " +
      "inotifywait -q -m -e close_write,create,delete,move --format . \"" + root.boardDir + "\""]
    stdout: SplitParser { onRead: root.reload() }
  }

  // ---- window --------------------------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "zed-quadro"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      anchors { top: true; right: true; bottom: true; left: true }

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.975)
        focus: root.opened

        Keys.onEscapePressed: {
          if (root.lockedNode) { root.lockedNode = null; root.focusNode = null }
          else root.opened = false
        }
        Keys.onPressed: function (e) {
          if (e.key === Qt.Key_R) { root.reload(); e.accepted = true }
          else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) {
            if (root.docs.length) { root.current = (root.current + 1) % root.docs.length; root.buildCurrent() }
            e.accepted = true
          } else if (e.key === Qt.Key_Left) {
            if (root.docs.length) { root.current = (root.current + root.docs.length - 1) % root.docs.length; root.buildCurrent() }
            e.accepted = true
          }
        }

        // ---- tabs ----
        Row {
          id: tabs
          anchors { top: parent.top; left: parent.left; leftMargin: 26; topMargin: 22 }
          spacing: 4

          Repeater {
            model: root.docs
            delegate: Rectangle {
              required property var modelData
              required property int index
              height: 32
              width: label.implicitWidth + 26
              radius: 5
              color: index === root.current
                ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
                : (hover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05) : "transparent")
              Text {
                id: label
                anchors.centerIn: parent
                text: modelData.title
                color: index === root.current ? Color.foreground : Color.muted
                font.family: "IBM Plex Mono, monospace"
                font.pixelSize: 12
                font.weight: index === root.current ? Font.DemiBold : Font.Normal
              }
              MouseArea {
                id: hover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { root.current = index; root.buildCurrent() }
              }
            }
          }
        }

        Text {
          anchors { top: tabs.top; right: parent.right; rightMargin: 26 }
          text: root.doc ? root.doc.file + "  ·  " + root.doc.mode : root.boardDir
          color: Color.muted
          opacity: 0.7
          font.family: "IBM Plex Mono, monospace"
          font.pixelSize: 11
        }

        Rectangle {
          id: rule
          anchors { top: tabs.bottom; left: parent.left; right: parent.right; topMargin: 14 }
          height: 1
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
        }

        // ---- empty / error ----
        Text {
          anchors.centerIn: parent
          visible: root.docs.length === 0
          horizontalAlignment: Text.AlignHCenter
          text: root.loadError !== "" ? root.loadError : "lendo..."
          color: Color.muted
          font.family: "IBM Plex Mono, monospace"
          font.pixelSize: 13
        }

        // ---- graph mode ----
        Item {
          anchors { top: rule.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
          visible: !!root.doc && root.doc.mode === "graph"

          Column {
            id: legend
            anchors { top: parent.top; left: parent.left; margins: 22 }
            spacing: 3
            Repeater {
              model: Object.keys(root.groups)
              delegate: Row {
                required property string modelData
                spacing: 8
                Rectangle {
                  width: 9; height: 9; radius: 4.5
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.groups[modelData].color
                }
                Text {
                  text: root.groups[modelData].label
                  color: Color.muted
                  font.family: "IBM Plex Mono, monospace"
                  font.pixelSize: 11
                }
              }
            }
          }

          Canvas {
            id: canvas
            anchors {
              top: parent.top; bottom: parent.bottom
              left: parent.left; right: inspector.left
              leftMargin: 200; rightMargin: 12; topMargin: 12; bottomMargin: 34
            }
            renderStrategy: Canvas.Cooperative

            // Publica o tamanho para o root simular contra a area real, e
            // repinta quando o tick avanca. Com dois monitores o ultimo a
            // redimensionar manda; para uma tela, que e o caso, e exato.
            onWidthChanged: if (width > 0) root.areaW = width
            onHeightChanged: if (height > 0) root.areaH = height
            Connections {
              target: root
              function onRepaintTickChanged() { canvas.requestPaint() }
            }

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var focus = root.lockedNode || root.focusNode
              var near = focus ? root.neighborsOf(focus).concat([focus]) : null
              var i

              for (i = 0; i < root.links.length; i++) {
                var l = root.links[i]
                var on = !focus || l.a === focus || l.b === focus
                ctx.strokeStyle = Color.foreground
                ctx.globalAlpha = on ? 0.40 : 0.09
                ctx.lineWidth = on ? 1.5 : 1
                ctx.beginPath(); ctx.moveTo(l.a.x, l.a.y); ctx.lineTo(l.b.x, l.b.y); ctx.stroke()
              }
              ctx.globalAlpha = 1

              for (i = 0; i < root.nodes.length; i++) {
                var n = root.nodes[i]
                var isNear = !near || near.indexOf(n) !== -1
                ctx.globalAlpha = isNear ? 1 : 0.18
                var col = root.colorOf(n)

                if (n.risk !== "") {
                  ctx.beginPath(); ctx.arc(n.x, n.y, n.r + 5, 0, Math.PI * 2)
                  ctx.strokeStyle = "#FF6257"; ctx.lineWidth = 1.4; ctx.stroke()
                }
                ctx.beginPath(); ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2)
                ctx.fillStyle = col; ctx.fill()

                if (n === focus) {
                  ctx.beginPath(); ctx.arc(n.x, n.y, n.r + 9, 0, Math.PI * 2)
                  ctx.strokeStyle = col; ctx.lineWidth = 1
                  ctx.globalAlpha = 0.5; ctx.stroke(); ctx.globalAlpha = 1
                }

                if ((n.r >= 8 || n === focus) && isNear) {
                  ctx.font = (n.r >= 10 ? "600 12px" : "500 11px") + " IBM Plex Mono"
                  ctx.textAlign = "center"
                  ctx.fillStyle = n === focus ? Color.foreground : Color.muted
                  ctx.fillText(n.id, n.x, n.y + n.r + 16)
                }
                ctx.globalAlpha = 1
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: root.draggingNode ? Qt.ClosedHandCursor
                         : root.focusNode ? Qt.PointingHandCursor : Qt.ArrowCursor

              function hit(mx, my) {
                var best = null, bd = 1e9
                for (var i = 0; i < root.nodes.length; i++) {
                  var n = root.nodes[i]
                  var d = Math.hypot(n.x - mx, n.y - my)
                  if (d < n.r + 12 && d < bd) { best = n; bd = d }
                }
                return best
              }
              onPositionChanged: function (e) {
                if (root.draggingNode) {
                  root.draggingNode.x = e.x; root.draggingNode.y = e.y
                  root.draggingNode.vx = 0; root.draggingNode.vy = 0
                  return
                }
                root.focusNode = hit(e.x, e.y)
              }
              onPressed: function (e) { root.draggingNode = hit(e.x, e.y) }
              onReleased: root.draggingNode = null
              onClicked: function (e) {
                var n = hit(e.x, e.y)
                root.lockedNode = (root.lockedNode === n) ? null : n
              }
              onExited: root.focusNode = null
            }
          }

          Rectangle {
            id: inspector
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 330
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)

            Column {
              anchors { fill: parent; margins: 20 }
              spacing: 11

              Text {
                text: "INSPETOR"
                color: Color.muted
                font.family: "IBM Plex Mono, monospace"
                font.pixelSize: 10
                font.letterSpacing: 1.6
              }
              Text {
                width: parent.width
                visible: !(root.lockedNode || root.focusNode)
                text: "Passe o mouse sobre um ponto. Clique trava, Esc solta.\n\n"
                    + "Tab troca de aba · R relê a pasta.\n\n"
                    + "O tamanho vem do número de ligações, então os centros aparecem sozinhos."
                color: Color.muted
                wrapMode: Text.WordWrap
                font.family: "IBM Plex Sans, sans-serif"
                font.pixelSize: 13
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.45
              }
              Text {
                width: parent.width
                visible: !!(root.lockedNode || root.focusNode)
                text: {
                  var n = root.lockedNode || root.focusNode
                  if (!n) return ""
                  var g = root.groups[n.group]
                  return (n.kind || "nó") + " · " + (g ? g.label : n.group)
                       + (root.lockedNode === n ? "  · TRAVADO" : "")
                }
                color: Color.muted
                font.family: "IBM Plex Mono, monospace"
                font.pixelSize: 10
                font.letterSpacing: 1.2
              }
              Text {
                width: parent.width
                visible: !!(root.lockedNode || root.focusNode)
                text: { var n = root.lockedNode || root.focusNode; return n ? n.id : "" }
                color: Color.foreground
                wrapMode: Text.WrapAnywhere
                font.family: "IBM Plex Mono, monospace"
                font.pixelSize: 15
                font.weight: Font.DemiBold
              }
              Text {
                width: parent.width
                visible: {
                  var n = root.lockedNode || root.focusNode
                  return !!(n && n.note !== "")
                }
                text: { var n = root.lockedNode || root.focusNode; return n ? n.note : "" }
                color: Color.foreground
                opacity: 0.82
                wrapMode: Text.WordWrap
                font.family: "IBM Plex Sans, sans-serif"
                font.pixelSize: 13
                lineHeightMode: Text.ProportionalHeight
                lineHeight: 1.45
              }
              Rectangle {
                width: parent.width
                visible: {
                  var n = root.lockedNode || root.focusNode
                  return !!(n && n.risk !== "")
                }
                height: riskText.implicitHeight + 20
                color: Qt.rgba(1, 0.38, 0.34, 0.10)
                Rectangle { width: 2; height: parent.height; color: "#FF6257" }
                Text {
                  id: riskText
                  anchors { fill: parent; margins: 10; leftMargin: 14 }
                  text: { var n = root.lockedNode || root.focusNode; return n ? n.risk : "" }
                  color: Color.foreground
                  wrapMode: Text.WordWrap
                  font.family: "IBM Plex Sans, sans-serif"
                  font.pixelSize: 12
                  lineHeightMode: Text.ProportionalHeight
                  lineHeight: 1.4
                }
              }
            }
          }
        }

        // ---- prose mode ----
        Flickable {
          anchors {
            top: rule.bottom; bottom: parent.bottom
            left: parent.left; right: parent.right
            topMargin: 26; bottomMargin: 26; leftMargin: 26; rightMargin: 26
          }
          visible: !!root.doc && root.doc.mode === "prose"
          contentWidth: width
          contentHeight: prose.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: prose
            width: Math.min(parent.width, 760)
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
            color: Color.foreground
            font.family: "IBM Plex Sans, sans-serif"
            font.pixelSize: 14
            lineHeightMode: Text.ProportionalHeight
            lineHeight: 1.2
            text: root.doc ? root.render(root.doc.body) : ""
          }
        }

        Text {
          anchors { left: parent.left; bottom: parent.bottom; margins: 22 }
          text: "Tab troca de aba · hover inspeciona · clique trava · R relê · Esc fecha"
          color: Color.muted
          opacity: 0.65
          font.family: "IBM Plex Mono, monospace"
          font.pixelSize: 10
        }
      }
    }
  }

  // ---- a small Markdown subset --------------------------------------------
  // Not a full renderer on purpose: this is a reading surface. Headings, rules,
  // lists, bold, italic and code spans cover what a note actually uses, and
  // anything unsupported still reads as its own source.
  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function inline(s) {
    return esc(s)
      .replace(/`([^`]+)`/g, '<span style="font-family:IBM Plex Mono">$1</span>')
      .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/\*([^*]+)\*/g, "<i>$1</i>")
  }

  function render(body) {
    var lines = String(body).replace(/```graph[\s\S]*?```/g, "").split("\n")
    var out = []
    var inList = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var t = line.trim()
      var h = /^(#{1,4})\s+(.*)$/.exec(t)
      if (h) {
        if (inList) { out.push("</ul>"); inList = false }
        var sizes = [23, 18, 15, 14]
        out.push('<p style="font-size:' + sizes[h[1].length - 1] +
                 'px;font-weight:600;margin:18px 0 6px">' + inline(h[2]) + "</p>")
        continue
      }
      if (/^([-*_])\1{2,}$/.test(t)) {
        if (inList) { out.push("</ul>"); inList = false }
        out.push('<p style="color:#888">&mdash;&mdash;&mdash;</p>')
        continue
      }
      var li = /^[-*]\s+(.*)$/.exec(t)
      if (li) {
        if (!inList) { out.push("<ul>"); inList = true }
        out.push("<li>" + inline(li[1]) + "</li>")
        continue
      }
      if (t === "") {
        if (inList) { out.push("</ul>"); inList = false }
        continue
      }
      if (inList) { out.push("</ul>"); inList = false }
      out.push('<p style="margin:0 0 12px">' + inline(t) + "</p>")
    }
    if (inList) out.push("</ul>")
    return out.join("")
  }
}
