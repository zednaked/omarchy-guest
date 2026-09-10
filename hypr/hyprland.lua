-- Ponto de entrada do Hyprland. O Omarchy e o dono; o HyDE e a rede.
--
-- Quem manda de verdade e a variavel de ambiente:
--
--     HYPRLAND_CONFIG=~/.config/hypr/hyprland.lua   (61-hyprland-config.conf)
--
-- O `00-hyde.sh` do HyDE define a dele com `${HYPRLAND_CONFIG:-...}`, ou seja,
-- so se ninguem tiver definido antes - e o environment.d ja rodou quando o uwsm
-- sobe o Hyprland. Por isso a inversao e um arquivo, e nao um patch no HyDE.
--
-- OS DOIS PAPEIS. Este arquivo pode ser carregado de duas formas, e a diferenca
-- e a razao de a tentativa de 03/09 ter falhado:
--
--   1. como RAIZ (o normal a partir de 09/09/2026): o Hyprland le este arquivo
--      primeiro, o global `hyde` nao existe, e carregamos a cadeia do Omarchy.
--
--   2. carregado PELO HyDE: se o override do env nao pegar, o Hyprland carrega
--      o hyde.lua, que no fim faz `check_require("hyprland")` e cai aqui. Ai o
--      global `hyde` JA existe, e carregar a cadeia do Omarchy por cima da do
--      HyDE poe as duas vivas ao mesmo tempo - duas barras, binds duplicados,
--      daemon duplicado. Foi exatamente isso em 03/09.
--
-- O guard abaixo cobre o caso 2 devolvendo a sessao de ontem, intacta, em vez
-- de uma sessao dobrada. Se voce logar e tudo estiver como antes da inversao,
-- o sintoma nao e "nao funcionou": e o env que nao chegou. Confira com
-- `echo $HYPRLAND_CONFIG` num terminal da sessao.
local home = os.getenv("HOME") or ""

if hyde then
  dofile(home .. "/.config/hypr/hyde-layer.lua")
  return
end

-- ---------------------------------------------------------------------------
-- Daqui para baixo: o Omarchy e a raiz.
-- Espelha o `config/hypr/hyprland.lua` deles, com os arquivos desta maquina.
-- ---------------------------------------------------------------------------

-- OMARCHY_PATH vem do ambiente (60-omarchy.conf). Sem ele o bootstrap procura
-- em /usr/share/omarchy, que aqui nao existe, e nada carrega.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- TESTE ANINHADO
--
-- `Hyprland -c este-arquivo` sobe uma instancia dentro da sessao atual e prova
-- que a cadeia carrega: binds, opcoes, `hyprctl configerrors`. O que ele NAO
-- prova e o login - ele ignora HYPRLAND_CONFIG e carrega o arquivo que voce
-- passou, que e justamente o cenario que no boot nao acontece.
--
-- Ele sobe UM quickshell a mais, porque o autostart do Omarchy chama
-- `omarchy-launch-shell`. Isso e o esperado, e morre junto com a instancia.
--
--     Hyprland -c ~/.config/hypr/hyprland.lua        # noutro terminal
--     hyprctl -i <sig> configerrors / binds / getoption
--     kill <pid da instancia>; pgrep -c quickshell   # tem que voltar a 1
--
-- HISTORIA, porque o erro foi de diagnostico e nao de codigo: em 09/09/2026 o
-- teste subia DOIS shells extras e eu gastei tres tentativas tentando calar o
-- autostart deles - stub em `package.loaded`, embrulho em `hl.exec_cmd`, um
-- executavel falso na frente do PATH. Nenhuma "funcionou", porque o segundo
-- shell nao vinha de la: vinha do `omarchy-lab/autostart.sh` que eu mesmo
-- tinha deixado no nosso `hypr/autostart.lua`. Aquele arquivo parece um saco
-- de ajustes e e um `exec omarchy-launch-shell` - o lancador do mundo antigo,
-- onde o autostart deles nunca rodava. Tirado ele, sobra um shell extra, que e
-- o certo.
--
-- Quem viu foi o Thiago, olhando a tela: "nesse ultimo que voce abriu tinha 2
-- barras". Eu estava contando processos e atribuindo a diferenca ao teste.
--
-- Nada de codigo de teste mora neste arquivo: o que roda no login e o que roda
-- no teste e o mesmo, que e a unica forma de o teste significar alguma coisa.

-- Defaults do Omarchy: helpers (a mesa `o`), autostart, binds, envs, looknfeel,
-- qconsole, input, windows, e o override do tema atual.
require("default.hypr.omarchy")

-- Os arquivos desta maquina, depois dos defaults deles: o que estiver aqui ganha.
require("hypr.monitors")   -- gerado pelo nwg-displays
require("hypr.input")      -- vazio: o default deles cobre
require("hypr.bindings")   -- vazio: SUPER+SPACE e SUPER+ALT+SPACE ja sao deles
require("hypr.looknfeel")  -- escrito pelo Omaland
require("hypr.zed")        -- o que e desta maquina e de mais ninguem
require("hypr.autostart")  -- daemons que o shell do Omarchy nao cobre
require("hypr.gaming")     -- o modo Gaming do HyDE, reescrito em 8 linhas

-- Toggles dinamicos deles (flags, no-gaps, aspect ratio).
require("default.hypr.toggles")

-- >>> omaland managed block >>>
-- Written by Omaland. Safe to hand-edit: Omaland re-reads this block
-- every time it opens, and only ever rewrites what's between the fences.
o.window(".*", { opacity = "1 1" })
-- <<< omaland managed block <<<
