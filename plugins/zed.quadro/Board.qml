pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Shared state for the board: the folder, whether anything changed since you
// last looked, and whether the overlay is open.
//
// This is the only part that stays loaded. It costs one blocked `inotifywait`
// and nothing else - no timer, no polling, no parsing. Documents are read and
// the graph simulated only while the overlay is actually open, which is what
// keeps the plugin from charging rent for a window nobody is looking at.
Singleton {
  id: root

  readonly property string dir: Quickshell.env("HOME") + "/.local/share/omarchy-guest/quadro"
  readonly property string seenFile:
    (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/omarchy-guest/quadro-seen"

  // Epoch seconds of the newest .md, and of the last time the overlay was
  // opened. A document is "new" when the folder moved on without you.
  property int newest: 0
  property int lastSeen: 0
  property int count: 0
  readonly property bool hasNew: root.newest > 0 && root.newest > root.lastSeen

  // The overlay follows this rather than owning it, so the bar icon and the IPC
  // can both open the board without either knowing about the other.
  property bool open: false

  signal changed()

  function scan() { if (!scanner.running) scanner.running = true }

  function markSeen() {
    root.lastSeen = root.newest
    seenWriter.running = true
  }

  // Newest mtime and file count in one line of output.
  Process {
    id: scanner
    command: ["sh", "-c",
      "d=\"" + root.dir + "\"; mkdir -p \"$d\"; " +
      "n=0; m=0; for f in \"$d\"/*.md; do [ -f \"$f\" ] || continue; " +
      "n=$((n+1)); t=$(stat -c %Y \"$f\"); [ \"$t\" -gt \"$m\" ] && m=$t; done; " +
      "printf '%s %s' \"$m\" \"$n\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text).trim().split(/\s+/)
        var m = parseInt(p[0] || "0", 10) || 0
        var n = parseInt(p[1] || "0", 10) || 0
        var moved = m !== root.newest
        root.newest = m
        root.count = n
        if (moved) root.changed()
      }
    }
  }

  Process {
    id: seenWriter
    command: ["sh", "-c",
      "f=\"" + root.seenFile + "\"; mkdir -p \"$(dirname \"$f\")\"; " +
      "printf '%s' \"" + root.lastSeen + "\" > \"$f\""]
  }

  Process {
    id: seenReader
    running: true
    command: ["sh", "-c", "cat \"" + root.seenFile + "\" 2>/dev/null || printf 0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.lastSeen = parseInt(String(text).trim(), 10) || 0
        root.scan()
      }
    }
  }

  // One watcher for the life of the session. Blocked on read it costs nothing;
  // polling on a timer would cost something every tick forever, for a folder
  // that changes a few times a day.
  Process {
    id: watcher
    running: true
    command: ["sh", "-c",
      "command -v inotifywait >/dev/null || exit 0; " +
      "inotifywait -q -m -e close_write,create,delete,move --format . \"" + root.dir + "\""]
    stdout: SplitParser { onRead: root.scan() }
  }

  // If inotifywait is missing the watcher exits immediately; fall back to a slow
  // poll so the icon is not silently dead. Half a minute is far below the rate
  // anyone writes to a board by hand.
  Timer {
    running: !watcher.running
    interval: 30000
    repeat: true
    onTriggered: root.scan()
  }
}
