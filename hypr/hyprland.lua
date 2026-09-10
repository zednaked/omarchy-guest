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

-- TESTE ANINHADO, e por que ele nao mora mais neste arquivo.
--
-- `Hyprland -c este-arquivo` sobe uma instancia dentro da sessao atual e prova
-- que a cadeia carrega: binds, opcoes, `hyprctl configerrors`. O que ele NAO
-- prova e o login - ele ignora HYPRLAND_CONFIG e carrega o arquivo que voce
-- passou, que e justamente o cenario que no boot nao acontece.
--
-- O problema pratico e que o autostart deles chama `omarchy-launch-shell`, e o
-- teste sobe um SEGUNDO quickshell brigando com o da sessao real pelos arquivos
-- em ~/.local/state/omarchy. Duas tentativas de resolver isso DENTRO do Lua
-- falharam, e ambas foram medidas em 09/09/2026:
--
--   1. `package.loaded["default.hypr.autostart"] = true` - inutil: o bootstrap
--      deles trata os prefixos `default.hypr` e `hypr` como recarregaveis, para
--      o `hyprctl reload` pegar edicao, e isso passa por cima do cache.
--   2. embrulhar `hl.exec_cmd` para filtrar o comando - tambem inutil: o
--      segundo shell subiu igual, pelo mesmo `omarchy-launch-shell`.
--
--   3. um `omarchy-launch-shell` falso na frente do PATH da instancia de teste
--      - tambem inutil, e essa foi a mais instrutiva: subiram DOIS shells. O
--      `hl.exec_cmd` nao herda o PATH que voce passou no lancamento; o comando
--      cai no shell de login (fish aqui), que remonta o PATH pelo proprio
--      conf.d antes de resolver o nome.
--
-- Entao: **o teste aninhado sobe um segundo quickshell, e ponto.** Ele nao
-- estraga a sessao - morre junto com a instancia - mas enquanto vive escreve
-- no mesmo ~/.local/state/omarchy do shell de verdade. Procedimento:
--
--     Hyprland -c ~/.config/hypr/hyprland.lua        # noutro terminal
--     hyprctl -i <sig> configerrors / binds / getoption
--     kill <pid da instancia>                        # e conferir com pgrep -c
--                                                    # quickshell que voltou a 1
--
-- Nada de teste mora neste arquivo: o que roda no login e o que roda no teste
-- e o mesmo codigo, que e a unica forma de o teste significar alguma coisa.

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
