-- O cursor no LOGIN, que o hook de tema nao alcanca.
--
-- O `omarchy-guest-theme-apply` escreve o cursor em tres lugares persistentes -
-- gtk settings.ini, ~/.icons/default/index.theme e gsettings - e aplica ao vivo
-- com `hyprctl setcursor`. Os tres primeiros valem para os APPS. O compositor
-- decide o dele no arranque, lendo XCURSOR_THEME e HYPRCURSOR_THEME do ambiente.
--
-- NUM GUEST ESSAS DUAS COSTUMAM SER DO HOST. O HyDE as exporta pelo
-- UWSM_FINALIZE_VARNAMES dele. Quando o host sai, elas somem - e o Hyprland
-- passa a subir com TAMANHO e sem TEMA, porque o `envs.lua` do Omarchy define
-- XCURSOR_SIZE e HYPRCURSOR_SIZE mas nao os nomes.
--
-- O sintoma engana: numa tela com scale 2 o cursor nasce minusculo, "conserta"
-- quando voce troca de tema - porque ai o hook roda `setcursor` - e volta a
-- quebrar no boot seguinte. Exatamente a armadilha que o THEMING.md descreve
-- para o wallpaper: um hook que repinta na troca de tema ainda perde o login.
-- Medido em 16/09/2026, no primeiro boot depois de o HyDE sair do disco.
--
-- A FONTE DA VERDADE e o `Inherits=` do index.theme, que o theme-apply escreve.
-- Ler dali em vez de fixar um nome aqui mantem um dono so: trocar o cursor no
-- theme-apply passa a valer no login sem tocar neste arquivo.
local home = os.getenv("HOME") or ""

local function primeiro_valor(caminho, padrao)
  local f = io.open(caminho, "r")
  if not f then return nil end
  for linha in f:lines() do
    local v = linha:match(padrao)
    if v and v ~= "" then f:close(); return v end
  end
  f:close()
  return nil
end

local tema = primeiro_valor(home .. "/.icons/default/index.theme", "^Inherits%s*=%s*(.-)%s*$")
local tamanho = primeiro_valor(home .. "/.config/gtk-3.0/settings.ini",
                               "^gtk%-cursor%-theme%-size%s*=%s*(%d+)") or "24"

if tema then
  -- Para o compositor e para tudo que ele lanca. XCURSOR_* cobre XWayland e os
  -- toolkits antigos; HYPRCURSOR_* e o caminho nativo do Hyprland, e e ele que
  -- faz o tamanho respeitar a escala do monitor.
  hl.env("XCURSOR_THEME", tema)
  hl.env("HYPRCURSOR_THEME", tema)
  hl.env("XCURSOR_SIZE", tamanho)
  hl.env("HYPRCURSOR_SIZE", tamanho)

  -- E o cinto, alem do suspensorio: `hl.env` entra no ambiente, mas quem ja
  -- montou o cursor nao releu nada. `setcursor` manda o compositor recarregar,
  -- e e a mesma chamada que o theme-apply faz na troca de tema - so que agora
  -- tambem no arranque.
  hl.on("hyprland.start", function()
    hl.exec_cmd(("hyprctl setcursor %s %s"):format(tema, tamanho))
  end)
end
