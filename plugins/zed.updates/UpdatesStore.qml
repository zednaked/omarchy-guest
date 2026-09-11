pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Estado do contador de atualizacoes. Um widget de barra e instanciado uma vez
// por monitor, entao o que tem estado (contagem, timer, processo) mora aqui, e
// o Panel.qml e so a vista.
//
// O motor vem de `vendor/hyde-updater` (originalmente do HyDE, GPL-3 - ver o
// NOTICE.md de la). Ele tem backend por gerenciador em vez de embrulhar um
// `pacman -Syu`, e publica exatamente o que uma barra precisa:
//
//   status  -> imprime {"text","tooltip","class"} no formato do waybar E grava
//              o inventario em $XDG_RUNTIME_DIR/omarchy-guest/update_info.json
//   up      -> abre um terminal com o atualizador interativo
//
// Entao este plugin nao reimplementa contagem: le a saida dele. O Omarchy nao
// tem equivalente - o atualizador dele nao reporta inventario nenhum -, e por
// isso esta parte vive no repo em vez de ser emprestada do host.
Singleton {
  id: root

  // Onde esta o motor. A ordem importa: a copia do omarchy-guest ganha da do
  // HyDE, para a maquina nao depender do host estar instalado. O caminho do
  // HyDE fica por ultimo so para quem ainda nao rodou `omarchy-guest install`.
  //
  // Nao da para testar existencia de arquivo daqui sem I/O sincrono, entao quem
  // resolve e o `resolver` abaixo: um `sh -c` que imprime o primeiro que existe.
  property string engine: ""
  readonly property string cachePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/omarchy-guest/update_info.json"

  // Total e detalhe por gerenciador. `managers` e uma lista de {name, count}.
  property int total: 0
  property var managers: []
  property bool checking: false
  property string lastError: ""

  // Minutos entre checagens. O `status` sai para a rede (checkupdates, yay),
  // entao nao e barato: o padrao e folgado de proposito, e o clique direito
  // forca na hora.
  property int intervalMinutes: 30

  readonly property string tooltip: {
    if (root.lastError !== "")
      return "Falha ao consultar: " + root.lastError
    if (root.checking && root.total === 0)
      return "Consultando atualizacoes..."
    if (root.total === 0)
      return "Sistema em dia"
    var linhas = ["Atualizacoes: " + root.total]
    for (var i = 0; i < root.managers.length; i++) {
      var m = root.managers[i]
      linhas.push("  " + m.name + ": " + m.count)
    }
    linhas.push("")
    linhas.push("Clique para atualizar - direito para reconsultar")
    return linhas.join("\n")
  }

  function applyManagers(lista) {
    var soma = 0
    for (var i = 0; i < lista.length; i++)
      soma += Number(lista[i].count) || 0
    root.managers = lista
    root.total = soma
  }

  // Leitura do arquivo de cache: da o numero na hora, no boot, sem esperar a
  // consulta de rede terminar. O `status` sobrescreve depois com o valor fresco.
  function loadCache() {
    cacheFile.reload()
  }

  function refresh() {
    if (probe.running || root.engine === "")
      return
    root.checking = true
    probe.running = true
  }

  function openUpdater() {
    updater.running = true
  }

  // Resolve o motor uma vez, no start. Sem ele o widget precisaria de um
  // caminho cravado, que e justamente o acoplamento que a vendorizacao tirou.
  Process {
    id: resolver
    running: true
    command: ["sh", "-c",
      "for c in \"$OMARCHY_GUEST_UPDATER\" " +
      "\"$HOME/.local/share/omarchy-guest/updater/system.update.py\" " +
      "\"$HOME/.local/lib/hyde/system.update.py\"; do " +
      "[ -n \"$c\" ] && [ -f \"$c\" ] && { printf %s \"$c\"; exit 0; }; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var caminho = text.trim()
        if (caminho === "") {
          root.lastError = "nenhum system.update.py encontrado"
          return
        }
        root.engine = caminho
        root.loadCache()
        root.refresh()
      }
    }
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    onLoaded: {
      try {
        var dados = JSON.parse(cacheFile.text())
        if (dados && dados.managers)
          root.applyManagers(dados.managers)
      } catch (e) {
        // Cache ausente ou pela metade nao e erro: o `status` resolve.
      }
    }
  }

  // Le o inventario do tooltip que o `status` imprime:
  //
  //   {"text":"󰮯 26","tooltip":"Updates 26\npacman: 26\nyay: 0","class":"updates"}
  //
  // Antes eu recarregava o arquivo de cache aqui, e estava errado: depois de
  // atualizar de verdade o contador continuava marcando o numero velho. O
  // stdout e a fonte fresca; o arquivo e so para o valor instantaneo do boot.
  function applyFromTooltip(tooltip) {
    var linhas = String(tooltip).split("\n")
    var lista = []
    for (var i = 0; i < linhas.length; i++) {
      var m = linhas[i].match(/^\s*([A-Za-z0-9_.-]+)\s*:\s*(\d+)\s*$/)
      if (m)
        lista.push({ name: m[1], count: Number(m[2]) })
    }
    if (lista.length > 0) {
      root.applyManagers(lista)
      return true
    }
    // Sem detalhe por gerenciador, ainda da para pegar o total da primeira linha.
    var t = String(tooltip).match(/(\d+)/)
    if (t) {
      root.managers = []
      root.total = Number(t[1])
      return true
    }
    return false
  }

  // `status` faz o trabalho de verdade e imprime o JSON do waybar.
  Process {
    id: probe
    command: ["python3", root.engine, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.checking = false
        try {
          var saida = JSON.parse(text)
          root.lastError = ""
          // Sistema em dia: o `status` devolve class "up-to-date", text vazio e
          // um tooltip SEM numero nenhum ("Packages are up to date"). Sem este
          // caso o parser nao acha digito e reporta erro justamente quando esta
          // tudo certo.
          if (String(saida["class"]) === "up-to-date" || String(saida.text).trim() === "") {
            root.managers = []
            root.total = 0
          } else if (!root.applyFromTooltip(saida.tooltip || saida.text || "")) {
            root.lastError = "nao consegui ler a contagem"
          }
        } catch (e) {
          root.lastError = "saida inesperada do system.update.py"
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = text.trim()
        if (msg !== "") {
          root.lastError = msg.split("\n")[0]
          root.checking = false
        }
      }
    }
  }

  // `up` abre o atualizador interativo no terminal (ele mesmo chama o
  // xdg-terminal-exec). Nao roda update por conta: quem digita a senha e
  // confirma a lista e o usuario.
  //
  // O `launch_interactive` do lado deles usa `subprocess.run`, que BLOQUEIA ate
  // o terminal fechar. Entao `running` virando false aqui significa "a janela
  // do atualizador foi fechada" - o momento exato de reconsultar. Sem isso o
  // contador so corrigia no proximo tick do timer, e ficava marcando o numero
  // velho depois de o sistema ja estar em dia.
  Process {
    id: updater
    command: ["python3", root.engine, "up"]
    onRunningChanged: {
      if (!running)
        root.refresh()
    }
  }

  Timer {
    interval: root.intervalMinutes * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  // Sem Component.onCompleted disparando consulta: quem inicia e o `resolver`,
  // depois de saber onde o motor esta.
}
