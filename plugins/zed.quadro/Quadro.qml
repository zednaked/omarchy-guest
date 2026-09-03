import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons

// Quadro - a board of Markdown documents, drawn as force-directed graphs or
// read as prose.
//
// A folder of .md files, one tab each. There is no "new document" button in
// here, because the point is the other direction: something with shell access
// writes a file, the bar mark lights up, and you open it when you feel like it.
//
// This half sleeps until opened. The watching lives in Board.qml, which costs
// one blocked inotifywait; nothing here reads, parses or simulates while the
// overlay is closed.
//
// Three things save back: node positions (Shift+E), the document text (E, then
// Ctrl+S) and the drawing (P). Format: docs/QUADRO-FORMAT.md.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // The board's open state is shared with the bar widget, so a click there and
  // an IPC call here are the same switch.
  property bool opened: Board.open

  readonly property string boardDir: Board.dir

  // The shell's own font, not a hardcoded family. The first version named
  // "IBM Plex Mono", the machine did not have it, every label fell back
  // silently, and the typography I thought I had chosen never happened.
  readonly property string mono: Style.fontFamily

  property var docs: []
  property int current: 0
  property string loadError: ""
  property string pendingShow: ""
  property string status: ""

  property var groups: ({})
  property var nodes: []
  property var links: []
  property var focusNode: null
  property var lockedNode: null
  property var draggingNode: null

  // Drawing area, published by the delegate.
  //
  // The Canvas id lives inside the Variants delegate - one instance per monitor
  // - and functions declared out here cannot see ids from in there. Reading
  // canvas.width from root threw ReferenceError and aborted the parse before it
  // assigned any nodes: an empty graph, with nothing on screen to say why.
  property real areaW: 1200
  property real areaH: 800
  property int repaintTick: 0

  // The simulation stops when it stops moving. Without this the board held 73%
  // of a core for as long as it was open, redrawing a settled graph - a still
  // image - sixty times a second.
  property bool settled: false
  property int calmFrames: 0

  property bool editing: false

  readonly property var doc: root.docs.length > 0 && root.current < root.docs.length
    ? root.docs[root.current] : null

  function wake() { root.settled = false; root.calmFrames = 0 }
  function flash(msg) { root.status = msg; statusTimer.restart() }
  Timer { id: statusTimer; interval: 2600; onTriggered: root.status = "" }

  // ---- loading -------------------------------------------------------------
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
  // filename and its body. Written as char codes because a control character in
  // the source does not survive being copied around.
  function ingest(raw) {
    var parts = String(raw).split(String.fromCharCode(30))
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var chunk = parts[i]
      if (chunk.trim() === "") continue
      var cut = chunk.indexOf(String.fromCharCode(31))
      if (cut < 0) continue
      out.push(root.parseDoc(chunk.substring(0, cut), chunk.substring(cut + 1)))
    }
    root.docs = out
    root.loadError = out.length === 0 ? "nenhum .md em " + root.boardDir : ""
    if (root.current >= out.length) root.current = 0
    if (root.pendingShow !== "") { if (!root.applyPending()) root.buildCurrent() }
    else root.buildCurrent()
  }

  // Matches on title, filename, or a fragment of either - whoever calls this
  // from a terminal should not have to remember the numeric prefix.
  function applyPending() {
    var want = root.pendingShow.toLowerCase()
    root.pendingShow = ""
    for (var i = 0; i < root.docs.length; i++) {
      var d = root.docs[i]
      if (d.title.toLowerCase().indexOf(want) >= 0 || d.file.toLowerCase().indexOf(want) >= 0) {
        root.current = i
        root.buildCurrent()
        return true
      }
    }
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
    return { file: file, title: title, mode: mode, body: text, raw: body }
  }

  // ---- graph parsing -------------------------------------------------------
  function buildCurrent() {
    root.focusNode = null
    root.lockedNode = null
    root.editing = false
    if (!root.doc || root.doc.mode !== "graph") {
      root.nodes = []; root.links = []; root.groups = {}
      return
    }
    var block = /```graph\s*\n([\s\S]*?)```/.exec(root.doc.body)
    var src = block ? block[1] : ""

    var groups = {}, nodes = [], byName = {}, pending = [], saved = {}
    var last = null
    var lines = src.split("\n")

    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim()
      if (t === "" || t.charAt(0) === "#") continue
      if (t.charAt(0) === "!") { if (last) last.risk = t.substring(1).trim(); continue }

      var g = /^group\s+(\S+)\s+(#[0-9A-Fa-f]{3,8})\s*(.*)$/.exec(t)
      if (g) { groups[g[1]] = { color: g[2], label: g[3] || g[1] }; continue }

      // `pos Nome x y` - written by Shift+E, read back as the starting layout.
      var p = /^pos\s+(.+?)\s+(-?[\d.]+)\s+(-?[\d.]+)$/.exec(t)
      if (p) { saved[p[1].trim()] = { x: parseFloat(p[2]), y: parseFloat(p[3]) }; continue }

      var l = /^(.+?)\s*->\s*(.+?)$/.exec(t)
      if (l && t.charAt(0) !== "[") { pending.push([l[1].trim(), l[2].trim()]); continue }

      var n = /^\[(\w+)\]\s*(.+)$/.exec(t)
      if (n) {
        var rest = n[2].split("::")
        var node = {
          id: rest[0].trim(), group: n[1],
          kind: (rest[1] || "").trim(), note: (rest[2] || "").trim(),
          risk: "", degree: 0, x: 0, y: 0, vx: 0, vy: 0, r: 6
        }
        nodes.push(node); byName[node.id] = node; last = node
      }
    }

    var links = []
    for (var q = 0; q < pending.length; q++) {
      var a = byName[pending[q][0]], b = byName[pending[q][1]]
      if (a && b && a !== b) { links.push({ a: a, b: b }); a.degree++; b.degree++ }
    }

    // Size from connectivity: the hubs appear without anyone declaring which
    // node matters.
    for (var k = 0; k < nodes.length; k++)
      nodes[k].r = Math.min(14, 5 + nodes[k].degree * 1.6)

    // Saved positions are a starting layout, not a pin. The simulation still
    // runs from there - a graph frozen in place stops showing structure, which
    // is the only reason to draw it this way.
    var wells = root.wellsFor(groups, root.areaW, root.areaH)
    for (var s = 0; s < nodes.length; s++) {
      var sv = saved[nodes[s].id]
      if (sv) { nodes[s].x = sv.x; nodes[s].y = sv.y }
      else {
        var well = wells[nodes[s].group] || { x: root.areaW / 2, y: root.areaH / 2 }
        var ang = (s / nodes.length) * Math.PI * 2
        nodes[s].x = well.x + Math.cos(ang) * (40 + (s % 5) * 24)
        nodes[s].y = well.y + Math.sin(ang) * (40 + (s % 5) * 24)
      }
      nodes[s].vx = 0; nodes[s].vy = 0
    }

    root.groups = groups
    root.nodes = nodes
    root.links = links
    root.wake()
  }

  // Wells sit on a circle, so any number of groups spreads evenly instead of
  // needing hand-placed quadrants.
  function wellsFor(groups, w, h) {
    var keys = Object.keys(groups), out = {}
    var cx = w / 2, cy = h / 2, rad = Math.min(w, h) * 0.30
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
    running: root.opened && root.nodes.length > 0 && !root.settled
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

    var energy = 0
    for (i = 0; i < ns.length; i++) {
      var n = ns[i]
      var well = wells[n.group]
      if (well) {
        n.vx += (well.x - n.x) * 0.0030
        n.vy += (well.y - n.y) * 0.0030
      }
      if (n === root.draggingNode) continue
      n.vx *= 0.86; n.vy *= 0.86
      n.x += n.vx; n.y += n.vy
      energy += n.vx * n.vx + n.vy * n.vy
      var m = n.r + 18
      n.x = Math.max(m, Math.min(w - m, n.x))
      n.y = Math.max(m, Math.min(h - m, n.y))
    }

    // Settle after the system has been quiet for a while, not on the first calm
    // frame: a graph passing through a still moment is not finished.
    if (energy < 0.05 * ns.length) {
      root.calmFrames++
      if (root.calmFrames > 40) root.settled = true
    } else {
      root.calmFrames = 0
    }
  }

  onOpenedChanged: {
    if (root.opened) {
      root.editing = false
      root.reload()
      root.wake()
      Board.markSeen()      // opening is what clears the mark on the bar
    }
  }

  // Only reload from the watcher while the board is on screen. Closed, this
  // whole half is inert and Board.qml does the watching for one process.
  Connections {
    target: Board
    function onChanged() { if (root.opened && !root.editing) root.reload() }
  }

  // ---- saving --------------------------------------------------------------
  FileView {
    id: writer
    path: root.doc ? root.boardDir + "/" + root.doc.file : ""
    printErrors: false
  }

  // 1. positions, back into the graph block as `pos` lines
  function savePositions() {
    if (!root.doc || root.doc.mode !== "graph") { root.flash("esta aba nao e grafo"); return }
    var body = root.doc.raw
    var block = /(```graph\s*\n)([\s\S]*?)(```)/.exec(body)
    if (!block) { root.flash("nao achei o bloco graph"); return }
    var inner = block[2].split("\n").filter(function (l) {
      return !/^\s*pos\s+/.test(l)
    }).join("\n").replace(/\n+$/, "")
    var lines = []
    for (var i = 0; i < root.nodes.length; i++) {
      var n = root.nodes[i]
      lines.push("pos " + n.id + " " + Math.round(n.x) + " " + Math.round(n.y))
    }
    writer.setText(body.substring(0, block.index) + block[1] + inner + "\n\n" +
                   lines.join("\n") + "\n" + block[3] +
                   body.substring(block.index + block[0].length))
    root.flash("posicoes salvas em " + root.doc.file)
  }

  // 2. the document text, from edit mode
  function saveText(newBody) {
    if (!root.doc) return
    writer.setText(newBody)
    root.flash("salvo: " + root.doc.file)
    root.editing = false
  }

  // 3. the drawing, as a PNG beside the document
  property string exportTarget: ""
  signal requestExport()
  function exportImage() {
    if (!root.doc || root.doc.mode !== "graph") { root.flash("esta aba nao e grafo"); return }
    root.exportTarget = root.boardDir + "/" + root.doc.file.replace(/\.md$/, "") + ".png"
    root.repaintTick++
    exportTimer.restart()
  }
  Timer { id: exportTimer; interval: 60; onTriggered: root.requestExport() }

  // ---- IPC -----------------------------------------------------------------
  // Without this the overlay cannot be opened at all: `opened` is only a
  // property, and something has to set it.
  IpcHandler {
    target: "quadro"
    function toggle(): string { Board.open = !Board.open; return Board.open ? "open" : "closed" }
    function open(): string { Board.open = true; return "ok" }
    function close(): string { Board.open = false; return "ok" }
    function reload(): string { root.reload(); return "ok" }

    // Open straight onto a document. This is what makes the board useful to an
    // agent: write the .md, then `omarchy-shell quadro show "mapa"`, instead of
    // asking a person to go find the tab.
    function show(name: string): string {
      root.pendingShow = name
      Board.open = true
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

  // ---- window --------------------------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      // Only on the focused output. The same simulation drawn on two screens
      // means two canvases fighting over one area size, and the second one is
      // wrong by construction.
      readonly property bool isTarget: {
        var f = Hyprland.focusedMonitor
        var want = f ? String(f.name || "") : ""
        if (want === "") return true
        return String(modelData.name || "") === want
      }

      visible: root.opened && isTarget
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "zed-quadro"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      anchors { top: true; right: true; bottom: true; left: true }

      // A FocusScope owns the keys, and nothing inside accepts focus by Tab -
      // otherwise the Flickable and the Canvas swallow it, and the footer's
      // promise that Tab changes tab is a lie.
      FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (e) {
          if (root.editing) {
            if (e.key === Qt.Key_Escape) { root.editing = false; e.accepted = true }
            return
          }
          switch (e.key) {
          case Qt.Key_Escape:
            if (root.lockedNode) { root.lockedNode = null; root.focusNode = null; root.repaintTick++ }
            else Board.open = false
            e.accepted = true; break
          case Qt.Key_Tab:
          case Qt.Key_Right:
            if (root.docs.length) { root.current = (root.current + 1) % root.docs.length; root.buildCurrent() }
            e.accepted = true; break
          case Qt.Key_Backtab:
          case Qt.Key_Left:
            if (root.docs.length) { root.current = (root.current + root.docs.length - 1) % root.docs.length; root.buildCurrent() }
            e.accepted = true; break
          case Qt.Key_R: root.reload(); root.flash("relido"); e.accepted = true; break
          case Qt.Key_E:
            if (e.modifiers & Qt.ShiftModifier) root.savePositions()
            else if (root.doc) root.editing = true
            e.accepted = true; break
          case Qt.Key_P: root.exportImage(); e.accepted = true; break
          case Qt.Key_Space: root.wake(); e.accepted = true; break
          }
        }

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.975)

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
                  font.family: root.mono
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
            text: root.status !== "" ? root.status
                : root.doc ? root.doc.file + "  ·  " + (root.editing ? "editando" : root.doc.mode)
                : root.boardDir
            color: root.status !== "" ? Color.foreground : Color.muted
            opacity: root.status !== "" ? 1 : 0.7
            font.family: root.mono
            font.pixelSize: 11
          }

          Rectangle {
            id: rule
            anchors { top: tabs.bottom; left: parent.left; right: parent.right; topMargin: 14 }
            height: 1
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)
          }

          Text {
            anchors.centerIn: parent
            visible: root.docs.length === 0
            text: root.loadError !== "" ? root.loadError : "lendo..."
            color: Color.muted
            font.family: root.mono
            font.pixelSize: 13
          }

          // ---- edit mode ----
          Rectangle {
            anchors {
              top: rule.bottom; bottom: parent.bottom
              left: parent.left; right: parent.right
              margins: 26
            }
            visible: root.editing
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04)
            radius: 6

            Flickable {
              anchors { fill: parent; margins: 16 }
              contentWidth: width
              contentHeight: editor.implicitHeight
              clip: true
              TextEdit {
                id: editor
                width: parent.width
                text: root.doc && root.editing ? root.doc.raw : ""
                color: Color.foreground
                selectionColor: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.25)
                font.family: root.mono
                font.pixelSize: 13
                wrapMode: TextEdit.WrapAnywhere
                focus: root.editing
                activeFocusOnTab: false
                Keys.onPressed: function (e) {
                  if (e.key === Qt.Key_Escape) { root.editing = false; e.accepted = true }
                  else if (e.key === Qt.Key_S && (e.modifiers & Qt.ControlModifier)) {
                    root.saveText(editor.text); e.accepted = true
                  }
                }
              }
            }
          }

          // ---- graph mode ----
          Item {
            anchors { top: rule.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
            visible: !root.editing && !!root.doc && root.doc.mode === "graph"

            Column {
              anchors { top: parent.top; left: parent.left; margins: 22 }
              spacing: 3
              Repeater {
                model: Object.keys(root.groups)
                delegate: Row {
                  required property string modelData
                  spacing: 8
                  Rectangle {
                    width: 9; height: 9; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.groups[modelData].color
                  }
                  Text {
                    text: root.groups[modelData].label
                    color: Color.muted
                    font.family: root.mono
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
              activeFocusOnTab: false

              onWidthChanged: if (width > 0 && win.isTarget) { root.areaW = width; root.wake() }
              onHeightChanged: if (height > 0 && win.isTarget) { root.areaH = height; root.wake() }

              Connections {
                target: root
                function onRepaintTickChanged() { canvas.requestPaint() }
                function onRequestExport() {
                  if (!win.isTarget) return
                  if (canvas.save(root.exportTarget)) root.flash("imagem: " + root.exportTarget)
                  else root.flash("nao consegui gravar a imagem")
                }
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
                    ctx.font = (n.r >= 10 ? "600 12px " : "500 11px ") + root.mono
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
                    root.wake()
                    return
                  }
                  var was = root.focusNode
                  root.focusNode = hit(e.x, e.y)
                  // Hover only repaints. It must not restart the simulation, or
                  // moving the mouse across a settled graph sets it drifting.
                  if (was !== root.focusNode) root.repaintTick++
                }
                onPressed: function (e) { root.draggingNode = hit(e.x, e.y); root.wake() }
                onReleased: root.draggingNode = null
                onClicked: function (e) {
                  var n = hit(e.x, e.y)
                  root.lockedNode = (root.lockedNode === n) ? null : n
                  root.repaintTick++
                }
                onExited: { root.focusNode = null; root.repaintTick++ }
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
                  font.family: root.mono
                  font.pixelSize: 10
                  font.letterSpacing: 1.6
                }
                Text {
                  width: parent.width
                  visible: !(root.lockedNode || root.focusNode)
                  text: "Passe o mouse sobre um ponto. Clique trava, Esc solta.\n\n"
                      + "O tamanho vem do numero de ligacoes, entao os centros aparecem sozinhos.\n\n"
                      + "E edita · Shift+E salva as posicoes · P exporta imagem"
                  color: Color.muted
                  wrapMode: Text.WordWrap
                  font.family: root.mono
                  font.pixelSize: 12
                  lineHeightMode: Text.ProportionalHeight
                  lineHeight: 1.35
                }
                Text {
                  width: parent.width
                  visible: !!(root.lockedNode || root.focusNode)
                  text: {
                    var n = root.lockedNode || root.focusNode
                    if (!n) return ""
                    var g = root.groups[n.group]
                    return (n.kind || "no") + " · " + (g ? g.label : n.group)
                         + (root.lockedNode === n ? "  · TRAVADO" : "")
                  }
                  color: Color.muted
                  font.family: root.mono
                  font.pixelSize: 10
                  font.letterSpacing: 1.2
                }
                Text {
                  width: parent.width
                  visible: !!(root.lockedNode || root.focusNode)
                  text: { var n = root.lockedNode || root.focusNode; return n ? n.id : "" }
                  color: Color.foreground
                  wrapMode: Text.WrapAnywhere
                  font.family: root.mono
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
                  font.family: root.mono
                  font.pixelSize: 12
                  lineHeightMode: Text.ProportionalHeight
                  lineHeight: 1.4
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
                    font.family: root.mono
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
            visible: !root.editing && !!root.doc && root.doc.mode === "prose"
            contentWidth: width
            contentHeight: prose.implicitHeight
            clip: true
            activeFocusOnTab: false
            boundsBehavior: Flickable.StopAtBounds

            Text {
              id: prose
              width: Math.min(parent.width, 760)
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.RichText
              wrapMode: Text.WordWrap
              color: Color.foreground
              font.family: root.mono
              font.pixelSize: 14
              text: root.doc ? root.render(root.doc.body) : ""
            }
          }

          Text {
            anchors { left: parent.left; bottom: parent.bottom; margins: 22 }
            text: root.editing
              ? "Ctrl+S salva · Esc descarta"
              : "Tab troca aba · E edita · Shift+E salva posicoes · P imagem · R rele · Esc fecha"
            color: Color.muted
            opacity: 0.65
            font.family: root.mono
            font.pixelSize: 10
          }
        }
      }
    }
  }

  // ---- a small Markdown subset --------------------------------------------
  function esc(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  function inline(s) {
    return esc(s)
      .replace(/`([^`]+)`/g, '<span style="opacity:0.72">$1</span>')
      .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
      .replace(/\*([^*]+)\*/g, "<i>$1</i>")
  }

  function render(body) {
    var lines = String(body).replace(/```graph[\s\S]*?```/g, "").split("\n")
    var out = [], inList = false
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim()
      var h = /^(#{1,4})\s+(.*)$/.exec(t)
      if (h) {
        if (inList) { out.push("</ul>"); inList = false }
        var sizes = [22, 18, 15, 14]
        out.push('<p style="font-size:' + sizes[h[1].length - 1] +
                 'px;font-weight:600;margin:20px 0 8px">' + inline(h[2]) + "</p>")
        continue
      }
      if (/^([-*_])\1{2,}$/.test(t)) {
        if (inList) { out.push("</ul>"); inList = false }
        out.push('<p style="opacity:0.4">&mdash;&mdash;&mdash;</p>')
        continue
      }
      var li = /^[-*]\s+(.*)$/.exec(t)
      if (li) {
        if (!inList) { out.push("<ul>"); inList = true }
        out.push("<li>" + inline(li[1]) + "</li>")
        continue
      }
      if (t === "") { if (inList) { out.push("</ul>"); inList = false } continue }
      if (inList) { out.push("</ul>"); inList = false }
      out.push('<p style="margin:0 0 12px">' + inline(t) + "</p>")
    }
    if (inList) out.push("</ul>")
    return out.join("")
  }
}
