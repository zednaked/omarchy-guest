pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "Art.js" as Art
import "Strains.js" as Strains

// O estado da planta: o save, o relogio e a simulacao.
//
// Esta e a metade que fica acordada. Fechado o overlay, o custo do plugin
// inteiro e um Timer de 60 s fazendo aritmetica sobre numeros que ja estao na
// memoria - nenhum processo, nenhum arquivo, nenhum parse. O `cat` do save
// acontece uma vez, na carga do shell, e uma vez a mais toda vez que o overlay
// abre (para adotar um save mais novo que outra sessao tenha escrito).
//
// A simulacao e a de src/app.rs do Ganja-TUI, traduzida. As divergencias
// deliberadas estao marcadas com DIVERGE e explicadas onde acontecem; sao
// quatro, e todas descem da mesma decisao: isto mora numa barra, nao numa
// janela que voce abre por um minuto.
Singleton {
  id: root

  // ---- configuracao --------------------------------------------------------
  // Escritas por Ganja.qml a partir do manifest (e, se houver, das settings da
  // barra). Os defaults aqui sao os mesmos do manifest, para o caso de o
  // overlay ainda nao ter carregado quando o primeiro tick acontecer.

  // Horas de jogo por hora real. O TUI usa 130000 (ciclo completo em 60 s), o
  // que numa barra significaria uma colheita por minuto. 40 da um ciclo de 90
  // dias em ~54 h de sessao - uma semana de uso normal.
  property real timeScale: 40

  // O fator original do Ganja-TUI. La ele nao e um modo, e o unico ritmo: o
  // ciclo de 90 dias em 60 segundos.
  property real turboScale: 130000

  // Quanto a agua e o NPK drenam, em relacao ao TUI. La a planta se rega
  // sozinha e o dreno so serve de animacao; aqui quem rega e voce, e 1.0 por
  // hora de jogo esvaziaria o vaso a cada duas horas e meia de sessao.
  property real careScale: 0.2

  readonly property string dir: Quickshell.env("HOME") + "/.local/share/omarchy-guest/ganja"
  readonly property string saveFile: root.dir + "/save.json"

  // ---- estado --------------------------------------------------------------

  // A planta, no formato do serde de src/domain/plant.rs. E a fonte da verdade;
  // as propriedades abaixo sao um espelho para o QML, porque mexer num campo de
  // um `var` nao emite sinal nenhum e a barra nunca saberia.
  property var plant: null
  property var harvests: []
  property int totalHarvests: 0
  property string visualMode: "Normal"
  property string lastTick: ""

  property bool loaded: false
  property bool open: false          // o overlay segue isto, como no zed.quadro

  // Modo automatico: a planta se cuida sozinha, com os mesmos limiares do TUI.
  // Desligado por padrao - ver DIVERGE 3 - e ligado com `a` no overlay.
  property bool autoCare: false

  // Turbo: a planta DE VERDADE rodando no fator do TUI. Escreve no save, as
  // colheitas contam, e o que acontecer aqui aconteceu.
  //
  // Nao vai para o save de proposito, e desliga sozinho quando o overlay fecha.
  // Um ritmo que queima um ciclo por minuto e uma coisa que se faz olhando; se
  // sobrevivesse ao fechar a janela ou ao reiniciar o shell, a planta iria
  // embora enquanto ninguem via, e o unico bem dela e o tempo acumulado.
  property bool turbo: false

  function toggleTurbo() {
    root.turbo = !root.turbo
    root.lastTickMs = Date.now()   // sem isto o primeiro passo cobre o intervalo inteiro
    if (!root.turbo) root.save()
    return root.turbo
  }

  // Tamanho e tipo da janela do overlay: cheio, grande, medio, pequeno, janela.
  // Mora aqui, e nao no overlay, porque tem que sobreviver ao save como
  // qualquer outra preferencia.
  property string windowMode: "cheio"

  // espelho para a UI
  property string stage: "Seedling"
  property string stageLabel: "Seedling"
  property string strainName: ""
  property int day: 1
  property real water: 60
  property real nutrients: 60
  property string health: "Excellent"
  property real temperature: 24
  property real humidity: 60
  property real rootDevelopment: 10
  property real canopyDensity: 5
  property real co2: 80
  property real lightAbsorption: 50
  property string seedHex: "0000000000000000"

  readonly property bool ready: root.stage === "ReadyToHarvest"
  readonly property bool thirsty: root.water < 20
  readonly property bool hungry: root.nutrients < 20
  // No modo automatico o ponto so acende para a colheita: avisar de sede uma
  // planta que se rega sozinha e pedir uma acao que nao existe.
  readonly property bool alerting: root.ready || (!root.autoCare && (root.thirsty || root.hungry))

  signal watered()
  signal fed()
  signal harvested(var result)

  // ---- modo demonstracao ---------------------------------------------------
  // Segurar `f` no overlay roda no fator original do TUI. Simula em cima de uma
  // copia: o save nao ve nada disso, e soltar a tecla devolve a planta onde ela
  // estava. E o que se grava para mostrar o plugin a alguem.
  property var fastPlant: null
  readonly property bool fast: root.fastPlant !== null
  readonly property var viewPlant: root.fastPlant !== null ? root.fastPlant : root.plant

  function startFast() {
    if (!root.plant) return
    root.fastPlant = JSON.parse(JSON.stringify(root.plant))
  }
  function stopFast() { root.fastPlant = null; root.publish() }
  function fastStep(seconds) {
    if (!root.fastPlant) return
    root.advance(root.fastPlant, (seconds / 3600.0) * 130000.0, true)
    root.publish()
  }

  // ---- relogio -------------------------------------------------------------

  property double lastTickMs: 0
  property double lastSaveMs: 0

  // Um timer, 60 s, aritmetica pura. A 40x cada tick avanca 0,67 hora de jogo -
  // resolucao de sobra para um icone que mostra estagio e um ponto de alerta.
  // No turbo o mesmo timer bate a cada 100 ms. Nao e capricho: a 130000x, um
  // tique de sessenta segundos avancaria 2160 horas de jogo - o ciclo inteiro
  // de uma vez, sem nada para ver. A 100 ms sao 3,6 horas por passo, que e o
  // ciclo completo em 60 segundos, exatamente como o TUI.
  Timer {
    interval: root.turbo ? 100 : 60000
    running: root.loaded
    repeat: true
    triggeredOnStart: false
    onTriggered: root.tick()
  }

  function tick() {
    if (!root.plant) return
    var now = Date.now()
    // DIVERGE 1 (SPEC 4b): o relogio e de sessao, nao de parede. O delta e
    // medido de verdade para o tick nao ficar devendo quando o sistema atrasa o
    // timer, mas e limitado a dois intervalos: se a maquina dormiu tres dias, a
    // planta dormiu junto. `last_tick` do save NUNCA e usado para avancar nada.
    var step = root.turbo ? 100 : 60000
    var delta = root.lastTickMs > 0 ? Math.min(now - root.lastTickMs, step * 2) : step
    root.lastTickMs = now

    var beforeStage = root.plant.stage
    var scale = root.turbo ? root.turboScale : root.timeScale
    root.advance(root.plant, (delta / 1000.0 / 3600.0) * scale, false)
    root.publish()

    // Grava quando o estagio vira (e um marco que doi perder) e, fora isso, no
    // maximo uma vez a cada dez minutos. A SPEC pede escrita so em acao do
    // usuario; sem isto um shell que reinicia sem descarregar direito perde as
    // horas acumuladas, que e o unico bem que esta planta tem.
    // No turbo o estagio vira a cada poucos segundos; gravar em cada virada
    // seriam cinco escritas por minuto para um estado que muda de novo em
    // seguida. O que interessa gravar la e o fim: `toggleTurbo` grava ao
    // desligar, e a regra dos dez minutos continua valendo para os dois.
    if (!root.turbo && root.plant.stage !== beforeStage) root.save()
    else if (now - root.lastSaveMs > 600000) root.save()
  }

  // ---- simulacao -----------------------------------------------------------
  // Porta de App::update_time (src/app.rs:100).

  function advance(p, hours, isFast) {
    if (!p || hours <= 0) return

    p.total_hours_elapsed += hours

    // DIVERGE 2: o TUI faz `days_alive = total_hours / 24`, o que da dia 0 no
    // comeco - e `calculate_stage(0)` cai no ramo `_`, ou seja "pronta para
    // colher". La isso dura meio segundo e ninguem ve. A 40x duraria 36
    // minutos, com um broto anunciando colheita. O piso e 1, que e o mesmo
    // valor com que Plant::new_random nasce.
    p.days_alive = Math.max(1, Math.floor(p.total_hours_elapsed / 24.0))

    var waterDrain = p.stage === "Vegetative" ? 1.0 : (p.stage === "Flowering" ? 0.8 : 0.5)
    p.water_level = Math.max(p.water_level - waterDrain * root.careScale * hours, 0.0)

    var nutrientDrain = p.stage === "Vegetative" ? 0.8 : (p.stage === "Flowering" ? 1.0 : 0.4)
    p.nutrient_level = Math.max(p.nutrient_level - nutrientDrain * root.careScale * hours, 0.0)

    // DIVERGE 3: o auto-cuidado do TUI nao esta ligado por padrao. La a planta
    // se cuida sozinha porque a ideia e assistir; aqui regar e a unica coisa que
    // voce faz, e uma planta que se rega sozinha faz do `w` um botao que nao
    // liga nada.
    //
    // Mas continua existindo, com os limiares e os valores exatos de
    // src/app.rs:128, atras do `a`: quem quer so olhar a planta crescer liga o
    // modo automatico e nunca mais pensa em agua. Note que o teto do TUI e
    // generoso mas nunca afoga - 40+50 e 50+40 param antes dos 95 que
    // `calculate_health` considera critico.
    if (root.autoCare) {
      if (p.water_level < 40.0) p.water_level = Math.min(p.water_level + 50.0, 100.0)
      if (p.nutrient_level < 50.0) p.nutrient_level = Math.min(p.nutrient_level + 40.0, 100.0)
    }

    p.co2_level = Math.min(80.0 + p.canopy_density * 0.2, 100.0)

    var lightBase = (p.stage === "Vegetative") ? 60.0
      : (p.stage === "PreFlower") ? 75.0
      : (p.stage === "Flowering" || p.stage === "ReadyToHarvest") ? 85.0 : 40.0
    p.light_absorption = Math.min(lightBase + p.canopy_density * 0.1, 100.0)

    var tempVariation = Math.sin(p.days_alive * 0.7) * 2.0
    p.temperature = Math.min(Math.max(24.0 + tempVariation, 20.0), 28.0)

    p.humidity = Math.min(50.0 + p.water_level * 0.2, 80.0)
    p.root_development = Math.min(p.days_alive / 90.0 * 100.0, 100.0)

    var canopyBase
    switch (p.stage) {
    case "Seed": case "Germination": canopyBase = 5.0; break
    case "Seedling": canopyBase = 15.0 * p.genetics.growth_rate; break
    case "Vegetative": canopyBase = (40.0 + p.days_alive * 0.8) * p.genetics.growth_rate; break
    case "PreFlower": canopyBase = (60.0 + p.days_alive * 0.6) * p.genetics.growth_rate; break
    default: canopyBase = (80.0 + p.days_alive * 0.2) * p.genetics.growth_rate
    }
    p.canopy_density = Math.min(canopyBase, 100.0)

    p.stage = root.stageFor(p.days_alive)

    if (p.days_alive >= 45 && p.light_cycle === "Veg18_6") p.light_cycle = "Flower12_12"

    p.health = root.healthFor(p.water_level, p.nutrient_level)

    // Resiliencia genetica amortece o efeito de saude ruim no crescimento.
    var hm
    switch (p.health) {
    case "Excellent": case "Good": hm = 1.0; break
    case "Fair": hm = 0.85 + p.genetics.resilience * 0.15; break
    case "Poor": hm = 0.65 + p.genetics.resilience * 0.35; break
    default: hm = 0.4 + p.genetics.resilience * 0.6
    }
    p.canopy_density *= hm

    var ch = p.care_history
    if (p.water_level >= 40.0 && p.water_level <= 80.0) ch.total_optimal_water_hours += hours
    if (p.nutrient_level >= 50.0 && p.nutrient_level <= 80.0) ch.total_optimal_nutrient_hours += hours
    ch.total_hours += hours

    if (p.water_level < 20.0) root.stress(p, "LowWater", "Moderate")
    if (p.water_level > 90.0) root.stress(p, "HighWater", "Moderate")
    if (p.nutrient_level < 30.0) root.stress(p, "LowNutrients", "Moderate")
    if (p.nutrient_level > 90.0) root.stress(p, "NutrientBurn", "Severe")

    // DIVERGE 4 (SPEC 4): o ciclo nao termina. O `auto_harvest` do TUI e o
    // comportamento unico, nao uma opcao - colheu, planta outra. O que se
    // guarda e o historico.
    if (p.stage === "ReadyToHarvest" && p.days_alive >= 96) root.harvestPlant(p, isFast)
  }

  function stageFor(days) {
    if (days <= 10) return "Seedling"
    if (days <= 40) return "Vegetative"
    if (days <= 48) return "PreFlower"
    if (days <= 85) return "Flowering"
    return "ReadyToHarvest"
  }

  function healthFor(w, n) {
    var wOpt = w >= 40.0 && w <= 80.0
    var nOpt = n >= 50.0 && n <= 80.0
    if (w < 10.0 || w > 95.0 || n < 20.0 || n > 95.0) return "Critical"
    if (!wOpt && !nOpt) return "Poor"
    if (!wOpt || !nOpt) return "Fair"
    if (w >= 50.0 && w <= 70.0 && n >= 60.0 && n <= 75.0) return "Excellent"
    return "Good"
  }

  // has_recent_stress: so registra se nao houve evento da mesma causa nos
  // ultimos cinco dias, olhando os dez ultimos eventos.
  function stress(p, cause, severity) {
    var ev = p.care_history.stress_events
    var from = Math.max(ev.length - 10, 0)
    var floorDay = Math.max(p.days_alive - 5, 0)
    for (var i = ev.length - 1; i >= from; i--)
      if (ev[i].cause === cause && ev[i].day >= floorDay) return
    ev.push({ day: p.days_alive, severity: severity, cause: cause })
  }

  // ---- acoes ---------------------------------------------------------------

  // Regar enche ate o TOPO DA FAIXA OTIMA, nao ate 100.
  //
  // `calculate_health` chama de critica a planta com agua acima de 95 - afogar
  // e tao ruim quanto secar. No TUI isso nunca acontece porque o auto-cuidado
  // so rega abaixo de 40 e soma 50, entao a agua nunca passa de ~90. Aqui quem
  // rega e voce, e dois cliques levariam a 100: a acao obvia, feita duas vezes,
  // deixaria a planta em estado critico sem avisar nada. Um botao que pune quem
  // o aperta esta errado, nao o usuario.
  //
  // O piso preserva um nivel mais alto que ja exista (um save vindo do TUI, por
  // exemplo): regar nunca tira agua.
  readonly property real waterCeiling: 70    // faixa excelente: 50-70
  readonly property real nutrientCeiling: 75 // faixa excelente: 60-75

  function pour(amount) {
    if (!root.plant || root.fast) return
    root.plant.water_level = Math.max(root.plant.water_level,
      Math.min(root.plant.water_level + amount, root.waterCeiling))
    root.plant.health = root.healthFor(root.plant.water_level, root.plant.nutrient_level)
    root.publish(); root.save(); root.watered()
  }

  function feed(amount) {
    if (!root.plant || root.fast) return
    root.plant.nutrient_level = Math.max(root.plant.nutrient_level,
      Math.min(root.plant.nutrient_level + amount, root.nutrientCeiling))
    root.plant.health = root.healthFor(root.plant.water_level, root.plant.nutrient_level)
    root.publish(); root.save(); root.fed()
  }

  function harvestNow() {
    if (!root.plant || root.fast) return false
    if (root.plant.stage !== "ReadyToHarvest") return false
    root.harvestPlant(root.plant, false)
    root.publish(); root.save()
    return true
  }

  function toggleAutoCare() {
    root.autoCare = !root.autoCare
    if (root.autoCare && root.plant) {
      // Ligar o automatico age na hora: esperar o proximo tick para socorrer
      // uma planta em estado critico seria uma espera sem motivo.
      root.advance(root.plant, 0.0001, false)
      root.publish()
    }
    root.save()
    return root.autoCare
  }

  function setWindowMode(mode) {
    if (mode === root.windowMode) return
    root.windowMode = mode
    root.save()
  }

  function cycleVisualMode() {
    switch (root.visualMode) {
    case "Normal": root.visualMode = "Zen"; break
    case "Zen": root.visualMode = "Rainbow"; break
    case "Rainbow": root.visualMode = "Matrix"; break
    default: root.visualMode = "Normal"
    }
    root.save()
  }

  // ---- colheita ------------------------------------------------------------
  // HarvestResult::from_plant (src/domain/harvest.rs) + replantio.

  function harvestPlant(p, isFast) {
    var ch = p.care_history
    var waterPct = ch.total_hours === 0 ? 100.0 : (ch.total_optimal_water_hours / ch.total_hours) * 100.0
    var nutrientPct = ch.total_hours === 0 ? 100.0 : (ch.total_optimal_nutrient_hours / ch.total_hours) * 100.0
    var careQuality = Math.max((waterPct + nutrientPct) / 200.0, 0.7)
    var stressPenalty = Math.min(ch.stress_events.length * 0.02, 0.3)

    var quality = Math.min(Math.max(careQuality * 100.0 * (1.0 - stressPenalty), 0.0), 100.0)
    var mult = 0.7 + (quality / 100.0) * 0.3

    var result = {
      strain_name: p.strain_name,
      harvest_day: p.days_alive,
      completed_at: new Date().toISOString(),
      weight_grams: p.genetics.yield_potential * careQuality * (1.0 - stressPenalty),
      quality_score: quality,
      thc_percent: p.genetics.thc_percent * mult,
      cbd_percent: p.genetics.cbd_percent * mult,
      // Extras do plugin: o que a aba de colheitas mostra e o TUI nao guarda.
      // Campos a mais nao incomodam o serde do Rust (ele ignora o que nao
      // conhece), entao o arquivo continua sendo o mesmo formato.
      stress_events: ch.stress_events.length,
      seed: root.seedOf(p)
    }

    var fresh = root.newPlant()

    if (isFast) {
      // Demonstracao: o resultado nao entra no historico nem no save. A copia
      // replanta para que segurar `f` mostre o ciclo inteiro, e nao so o fim.
      for (var k in fresh) p[k] = fresh[k]
      return
    }

    var list = root.harvests.slice()
    list.push(result)
    // Cem colheitas e o teto. Um save que cresce para sempre e um vazamento com
    // outro nome; a decima colheita ja tem dez historias atras dela.
    while (list.length > 100) list.shift()
    root.harvests = list
    root.totalHarvests += 1
    root.plant = fresh
    root.harvested(result)
  }

  // ---- planta nova ---------------------------------------------------------
  // Plant::new_random + Genetics::random.

  function rand(min, max) { return min + Math.random() * (max - min) }

  function uuid() {
    var h = "0123456789abcdef"
    var s = ""
    for (var i = 0; i < 32; i++) {
      var d
      if (i === 12) d = 4                                     // versao 4
      else if (i === 16) d = 8 + Math.floor(Math.random() * 4) // variante
      else d = Math.floor(Math.random() * 16)
      s += h.charAt(d)
      if (i === 7 || i === 11 || i === 15 || i === 19) s += "-"
    }
    return s
  }

  function newPlant() {
    var strain = Strains.STRAINS[Math.floor(Math.random() * Strains.STRAINS.length)]

    var yieldBase = strain.yield_potential === "High" ? root.rand(100, 150)
      : strain.yield_potential === "Medium" ? root.rand(70, 110)
      : strain.yield_potential === "Low" ? root.rand(50, 80) : root.rand(50, 150)

    var resilience = strain.difficulty === "Easy" ? root.rand(0.7, 1.0)
      : strain.difficulty === "Medium" ? root.rand(0.4, 0.7)
      : strain.difficulty === "Hard" ? root.rand(0.0, 0.4) : root.rand(0.0, 1.0)

    var quality = (strain.type === "Sativa" || strain.type === "Indica") ? root.rand(80, 100)
      : strain.type === "Hybrid" ? root.rand(85, 100) : root.rand(70, 100)

    return {
      id: root.uuid(),
      strain_name: strain.name,
      stage: "Seedling",
      planted_at: new Date().toISOString(),
      // DIVERGE 5: a planta nasce no dia 5, nao no dia 1.
      //
      // O tronco so aparece quando `day * growth_rate >= 1`, e growth_rate e
      // 0,22 a 0,25 - ou seja, dos dias 1 ao 4 a arte e um vaso com terra e mais
      // nada. No TUI isso dura tres segundos e ninguem chega a ver. A 40x dura
      // tres horas, e sao justamente as tres primeiras horas depois de instalar
      // o plugin: o overlay estreia com uma caixa vazia e parece quebrado.
      days_alive: 5,
      total_hours_elapsed: 5 * 24.0,
      water_level: 60.0,
      nutrient_level: 60.0,
      light_cycle: "Veg18_6",
      health: "Excellent",
      genetics: {
        yield_potential: yieldBase,
        growth_rate: root.rand(0.9, 1.1),
        resilience: resilience,
        quality_ceiling: quality,
        strain_info: JSON.parse(JSON.stringify(strain)),
        thc_percent: root.rand(strain.thc_min, strain.thc_max),
        cbd_percent: root.rand(strain.cbd_min, strain.cbd_max)
      },
      care_history: {
        total_hours: 0.0,
        total_optimal_water_hours: 0.0,
        total_optimal_nutrient_hours: 0.0,
        water_optimal_percentage: 100.0,
        nutrient_optimal_percentage: 100.0,
        light_cycle_correct: true,
        stress_events: []
      },
      co2_level: 80.0,
      light_absorption: 50.0,
      temperature: 24.0,
      humidity: 60.0,
      root_development: 10.0,
      canopy_density: 5.0
    }
  }

  // O seed da arte e `plant.id.as_u128() as u64` (growing.rs:105): os 64 bits
  // baixos do uuid, ou seja os 16 ultimos digitos hexadecimais.
  function seedOf(p) {
    if (!p || !p.id) return "0000000000000000"
    var h = String(p.id).replace(/[^0-9a-fA-F]/g, "")
    while (h.length < 16) h = "0" + h
    return h.substring(h.length - 16).toLowerCase()
  }

  // ---- espelho para a UI ---------------------------------------------------

  function publish() {
    var p = root.viewPlant
    if (!p) return
    root.stage = p.stage
    root.stageLabel = Art.stageLabel(p.stage)
    root.strainName = p.strain_name
    root.day = p.days_alive
    root.water = p.water_level
    root.nutrients = p.nutrient_level
    root.health = p.health
    root.temperature = p.temperature
    root.humidity = p.humidity
    root.rootDevelopment = p.root_development
    root.canopyDensity = p.canopy_density
    root.co2 = p.co2_level
    root.lightAbsorption = p.light_absorption
    root.seedHex = root.seedOf(p)
  }

  // ---- persistencia --------------------------------------------------------
  // Formato: os mesmos campos da serializacao serde de App (src/app.rs), em
  // arquivo proprio. Copiar este save por cima do ~/.local/share/ganjatui/
  // save.json leva a planta para o TUI e vice-versa.

  function snapshot() {
    return {
      current_plant: root.plant,
      harvest_history: root.harvests,
      last_tick: new Date().toISOString(),
      total_harvests: root.totalHarvests,
      // No TUI isto e uma opcao; aqui e o comportamento, e gravar true mantem
      // os dois lados de acordo se alguem abrir o save no TUI.
      auto_harvest: true,
      visual_mode: root.visualMode,
      // Campos so do plugin. O serde do Rust ignora o que nao conhece, entao o
      // arquivo continua sendo o mesmo formato do TUI.
      auto_care: root.autoCare,
      window_mode: root.windowMode
    }
  }

  function adopt(data, fromDisk) {
    if (!data || !data.current_plant) return false
    root.plant = data.current_plant
    root.harvests = Array.isArray(data.harvest_history) ? data.harvest_history : []
    root.totalHarvests = data.total_harvests || 0
    root.visualMode = data.visual_mode || "Normal"
    root.autoCare = data.auto_care === true
    root.windowMode = data.window_mode || "cheio"
    root.lastTick = data.last_tick || ""

    // Saves antigos (ou do TUI) podem nao ter tudo. Preencher em vez de quebrar.
    var p = root.plant
    if (p.total_hours_elapsed === undefined) p.total_hours_elapsed = (p.days_alive || 1) * 24
    if (p.days_alive === undefined) p.days_alive = Math.max(1, Math.floor(p.total_hours_elapsed / 24))
    if (!p.care_history) p.care_history = root.newPlant().care_history
    if (!p.care_history.stress_events) p.care_history.stress_events = []
    if (p.care_history.total_hours === undefined) p.care_history.total_hours = 0
    if (p.care_history.total_optimal_water_hours === undefined) p.care_history.total_optimal_water_hours = 0
    if (p.care_history.total_optimal_nutrient_hours === undefined) p.care_history.total_optimal_nutrient_hours = 0
    if (!p.stage) p.stage = root.stageFor(p.days_alive)
    if (!p.health) p.health = root.healthFor(p.water_level, p.nutrient_level)

    root.publish()
    return true
  }

  Process {
    id: reader
    running: true
    command: ["sh", "-c",
      "find \"" + root.dir + "\" -maxdepth 1 -name 'save.json.*.tmp' -mmin +5 -delete 2>/dev/null; " +
      "cat \"" + root.saveFile + "\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text).trim()
        var ok = false
        if (raw !== "") {
          try { ok = root.adopt(JSON.parse(raw), true) }
          catch (e) { console.warn("zed.ganja: save ilegivel, comecando de novo:", e) }
        }
        if (!ok) {
          root.plant = root.newPlant()
          root.publish()
          root.save()
        }
        root.lastTickMs = Date.now()
        root.loaded = true
      }
    }
  }

  // Releitura ao abrir o overlay. Duas instancias do shell nao se resolvem com
  // lock: quem escreveu por ultimo ganha, e a unica hora em que vale a pena
  // perguntar ao disco e quando alguem vai olhar.
  Process {
    id: rereader
    command: ["sh", "-c", "cat \"" + root.saveFile + "\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text).trim()
        if (raw === "") return
        try {
          var data = JSON.parse(raw)
          var theirs = Date.parse(data.last_tick || "")
          var ours = Date.parse(root.lastTick || "")
          if (isFinite(theirs) && (!isFinite(ours) || theirs > ours)) root.adopt(data, true)
        } catch (e) { /* save sendo escrito neste instante; o mv resolve */ }
      }
    }
  }

  function reread() { if (!rereader.running) rereader.running = true }

  // Escrita atomica: o conteudo vai por stdin para um `.tmp` no mesmo
  // diretorio e so entao um `mv`. Escrever por cima do arquivo direto deixa uma
  // janela em que o TUI (ou a outra instancia do shell) le um JSON pela metade.
  property string pending: ""
  property bool dirty: false

  Process {
    id: writer
    stdinEnabled: true
    // O `.tmp` leva o PID do shell no nome: duas instancias do shell gravando
    // ao mesmo tempo num `save.json.tmp` compartilhado produzem um arquivo
    // costurado de dois JSONs, que e pior que qualquer corrida que o mv evita.
    command: ["sh", "-c",
      "d=\"" + root.dir + "\"; mkdir -p \"$d\"; t=\"$d/save.json.$$.tmp\"; " +
      "cat > \"$t\" && mv -f \"$t\" \"$d/save.json\" || rm -f \"$t\""]
    onStarted: {
      writer.write(root.pending)
      // Isto e o que fecha o stdin, e por isso `flush()` reabre antes de cada
      // rodada: atribuir `false` ao que ja e `false` nao e transicao, nao emite
      // nada e o pipe fica aberto. A segunda gravacao entao chega inteira ao
      // `.tmp`, o `cat` nunca ve o EOF, o `mv` nunca roda, e o save para no
      // tempo - com o arquivo certo em disco, com o nome errado.
      writer.stdinEnabled = false
    }
    onExited: {
      if (root.dirty) { root.dirty = false; root.flush() }
    }
  }

  function flush() {
    writer.stdinEnabled = true
    writer.running = true
  }

  function save() {
    if (root.fast) return          // a demonstracao nunca escreve
    if (!root.plant) return
    var snap = root.snapshot()
    root.lastTick = snap.last_tick
    root.pending = JSON.stringify(snap)
    root.lastSaveMs = Date.now()
    // Uma escrita em voo: marca e deixa o onExited pegar. Chamar de novo agora
    // abortaria o `cat` no meio.
    if (writer.running) root.dirty = true
    else root.flush()
  }

  Component.onDestruction: {
    if (root.loaded && root.plant && !root.fast) {
      // Sincrono de proposito: o processo esta indo embora e um Process
      // assincrono nao sobrevive para escrever.
      var snap = JSON.stringify(root.snapshot())
      Quickshell.execDetached(["sh", "-c",
        "d=\"" + root.dir + "\"; mkdir -p \"$d\"; t=\"$d/save.json.$$.tmp\"; " +
        "printf '%s' \"$1\" > \"$t\" && mv -f \"$t\" \"$d/save.json\" || rm -f \"$t\"",
        "sh", snap])
    }
  }
}
