-- Os defaults de manipulacao de janela que um guest vindo de outro host espera.
--
-- Carregue DEPOIS dos defaults do Omarchy (`require("hypr.bindings")` no seu
-- hyprland.lua, ou copie para `~/.config/hypr/bindings.lua`). Rebindar a mesma
-- combinacao aqui ganha da deles.
--
-- A regra deste arquivo: **`o.rebind`, nunca `o.bind`, para tecla ja ocupada.**
-- `bind` SOMA - as duas acoes passam a disparar no mesmo gesto e o
-- `hyprctl binds` mostra a tecla duas vezes, sem erro nenhum no log. `rebind`
-- remove a existente antes de adicionar. Custou uma sessao descobrir isso com
-- SUPER + P disparando screenshot e "pseudo window" ao mesmo tempo.
--
-- Confira o que existe antes de escrever linha nova:
--   omarchy menu keybindings --print
--   hyprctl binds -j | jq -r '.[] | select(.modmask==64) | .key' | sort | uniq -d

-- SUPER + W: alternar flutuante/lado a lado.
--
-- O Omarchy binda W e Q para o MESMO `close window`
-- (default/hypr/bindings/tiling.lua:1-2) - uma tecla desperdicada. No HyDE
-- SUPER + W era o toggle de flutuante. Devolvendo isso, SUPER + Q fica sendo o
-- unico fechar janela e nada se perde.
--
-- O SUPER + T deles continua fazendo o mesmo, de proposito: T e o mapa do
-- Omarchy, W e a memoria muscular de quem chegou de fora.
o.rebind("SUPER + W", "Alternar flutuante/lado a lado", hl.dsp.window.float({ action = "toggle" }))

-- SUPER + P: screenshot de regiao.
--
-- No Omarchy o gesto e a tecla PRINT, que continua valendo. Esta linha so
-- devolve o atalho de quem vem do HyDE (`hyde.sh.screenshot.snip()`), usando o
-- comando deles.
--
-- `rebind` e obrigatorio: SUPER + P ja e "Pseudo window" no Omarchy
-- (tiling.lua:6). Com `bind`, os dois conviviam.
o.rebind("SUPER + P", "Screenshot de regiao", "omarchy-capture-screenshot")

-- SUPER + A: menu de apps.
--
-- O equivalente do Omarchy ja esta em SUPER + ALT + SPACE; isto so devolve o
-- atalho de uma tecla. Nao ha conflito, entao `bind` basta.
o.bind("SUPER + A", "Menu de apps", "omarchy-menu toggle apps")

-- ---------------------------------------------------------------------------
-- Resize por borda e por canto, sem borda visivel.
--
-- Nao e bind, mas e a mesma historia: manipular janela com o mouse do jeito que
-- a mao ja sabe. Fica aqui para nao virar um quinto arquivo.
--
-- O Omarchy vem com `extend_border_grab_area = 15` e `resize_on_border = false`.
-- Os 15px nao fazem nada sozinhos - a opcao so entra em jogo com o resize por
-- borda ligado. O sintoma e exatamente este: a configuracao parece pronta,
-- `getoption` mostra a area de agarre certa, e arrastar o canto nao faz nada.
--
-- **Nao aumente o `border_size` para resolver isso.** Foi a primeira tentativa
-- aqui e nao e o problema: com `resize_on_border = true` a area de agarre sao os
-- 15px em volta da janela, invisiveis. `border_size = 0` continua valendo e nao
-- e preciso moldura para ter canto.
--
-- Se o alvo ficar dificil de acertar, suba `extend_border_grab_area` para 20-25
-- em vez de desenhar borda.
hl.config({
  general = {
    resize_on_border = true,
  },
})
