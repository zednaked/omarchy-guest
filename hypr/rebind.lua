-- O `rebind` que esta versao do Omarchy nao tem.
--
-- O PROBLEMA. `o.bind` numa tecla que o Omarchy ja usa nao substitui: SOMA. Os
-- dois dispatchers disparam no mesmo gesto, `hyprctl binds` lista a tecla duas
-- vezes e nada e logado. Foi o que aconteceu no macarch em 16/09/2026, na
-- inversao de posse: SUPER+ALT+G ficou com "Move active window out of group"
-- (default/hypr/bindings/tiling.lua) e o game mode ao mesmo tempo.
--
-- POR QUE PRECISA DISTO. O `hl.bind` do Hyprland devolve um objeto com
-- `:unbind()` - o proprio Omarchy usa em bindings/utilities.lua:77 para soltar
-- os binds de captura de tela. Mas o `o.bind` deles DESCARTA esse retorno,
-- entao quem carrega depois nao tem como alcancar o bind que quer trocar.
--
-- O `hypr/bindings.lua` do repo omarchy-guest chama `o.rebind`, que existe num
-- Omarchy mais novo; na segunda maquina nao existe (conferido em helpers.lua).
--
-- Onde `o.rebind` JA existe, o dele ganha e este arquivo e peso morto -
-- carregar assim mesmo nao custa nada e faz uma config so servir nas duas.
--
-- COMO FUNCIONA. Este arquivo embrulha `hl.bind` e guarda cada objeto por
-- combo normalizado. Tem que ser carregado ANTES de `default.hypr.omarchy`,
-- senao os binds deles nascem fora do registro e nao ha o que soltar.
local registro = {}

-- IDEMPOTENTE. O bootstrap do Omarchy limpa `package.loaded` dos modulos
-- `hypr.*` a cada `hyprctl reload`, entao este arquivo roda de novo - e nesse
-- momento `hl.bind` JA e o embrulho. Sem guardar o original num global, cada
-- reload embrulharia o embrulho, empilhando camadas com registros mortos.
local bind_original = _G.__guest_bind_original or hl.bind
_G.__guest_bind_original = bind_original

-- "SUPER + ALT + G" e "ALT + SUPER + G" sao o mesmo combo. Ordenar as partes
-- torna a chave independente de como foi escrito.
local function normalizar(keys)
	local partes = {}
	for p in tostring(keys):upper():gmatch("[^%s+]+") do
		table.insert(partes, p)
	end
	table.sort(partes)
	return table.concat(partes, "+")
end

hl.bind = function(keys, ...)
	local kb = bind_original(keys, ...)
	local chave = normalizar(keys)
	registro[chave] = registro[chave] or {}
	table.insert(registro[chave], kb)
	return kb
end

local M = {}

-- Solta todos os binds ja registrados no combo. Devolve quantos soltou - zero
-- significa que a tecla estava livre, e ai `o.bind` sozinho ja bastava.
function M.unbind(keys)
	local chave = normalizar(keys)
	local n = 0
	for _, kb in ipairs(registro[chave] or {}) do
		if type(kb) == "table" or type(kb) == "userdata" then
			local ok = pcall(function() kb:unbind() end)
			if ok then n = n + 1 end
		end
	end
	registro[chave] = nil
	return n
end

-- Substitui de verdade: solta o que houver e bota o seu no lugar.
function M.rebind(keys, description, dispatcher, options)
	M.unbind(keys)
	o.bind(keys, description, dispatcher, options)
end

return M
