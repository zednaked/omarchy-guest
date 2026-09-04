-- Modo Gaming: o substituto do workflow `gaming` do HyDE.
--
-- O HyDE tinha cinco workflows (`~/.local/share/hypr/lua/workflows/`) e voce
-- usava um: `gaming`. Ele fazia duas coisas, e as duas cabem aqui.
--
--   1. desligar o que o compositor gasta a toa: sombra, blur, arredondamento,
--      opacidade, gaps, e forcar toda janela opaca
--   2. silenciar notificacao - pelo IPC do proprio shell (setDnd), que
--      existe em qualquer guest, ao contrario do dnd.sh do omarchy-lab
--
-- O `opaque = true` do original nao foi copiado. Ele era a razao de existirem as
-- duas window rules de transparencia no hyprland.lua antigo, que passavam a vida
-- desfazendo o efeito dele. Regra de janela se acumula em vez de sobrescrever,
-- entao ligar e desligar `opaque` por toggle nao volta atras: o que sai ligando
-- fica. Sem ele o ganho de blending se perde, e era o menor dos cinco itens.
--
-- Ligar/desligar:
--   hyprctl dispatch exec 'omarchy-toggle gaming'   (se registrar como toggle)
-- ou direto, que e o que o bind abaixo faz.

local gaming = {}

local ligado = false

-- Os valores de volta sao os da SUA maquina - leia os reais com
-- `hyprctl getoption decoration:rounding` etc. antes de copiar estes, que
-- vieram da maquina de referencia (looknfeel.lua, bloco do Omaland). Se
-- mexer nos sliders depois, ajuste aqui tambem, ou o desligar devolve o
-- valor errado.
local normal = {
	decoration = {
		rounding = 14,
		active_opacity = 1,
		inactive_opacity = 0.84,
		fullscreen_opacity = 1,
		blur = { enabled = false },
		shadow = { enabled = false },
	},
	general = {
		gaps_in = 5,
		gaps_out = 5,
		border_size = 1,
	},
}

local jogo = {
	decoration = {
		rounding = 0,
		active_opacity = 1,
		inactive_opacity = 1,
		fullscreen_opacity = 1,
		blur = { enabled = false, xray = true },
		shadow = { enabled = false },
	},
	general = {
		gaps_in = 0,
		gaps_out = 0,
		border_size = 1,
	},
}

local run = (os.getenv("HOME") or "") .. "/.local/share/omarchy-guest/bin/omarchy-guest-run "

local function dnd(mudo)
	hl.exec_cmd(run .. "omarchy-shell -q notifications setDnd " .. mudo)
end

function gaming.set(ativo)
	ligado = ativo and true or false
	hl.config(ligado and jogo or normal)
	dnd(ligado and "true" or "false")
	hl.exec_cmd(run .. "omarchy-osd -m " .. (ligado and "'Modo Gaming'" or "'Modo normal'"))
end

function gaming.toggle()
	gaming.set(not ligado)
end

-- Cheque o combo contra o mapa do SEU host antes de copiar: num HyDE padrao
-- SUPER+SHIFT+G colide com o game launcher. No macarch o certo foi
-- SUPER+ALT+G com { locked = true }, substituindo o game mode do proprio
-- HyDE - flags iguais as dele, senao os dois binds ficam vivos no combo.
o.bind("SUPER + SHIFT + G", "Modo Gaming", function()
	gaming.toggle()
end)

_G.gaming = gaming
return gaming
