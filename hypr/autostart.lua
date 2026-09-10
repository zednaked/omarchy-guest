-- Autostart e ambiente do usuario. Carregado depois do
-- `default/hypr/autostart.lua` do Omarchy, entao aqui fica SOMENTE o que e
-- desta maquina e o que o shell deles nao cobre.
--
-- Revisado em 09/09/2026, depois da auditoria que desligou os units duplicados
-- do HyDE: cada linha abaixo existe porque NADA no Omarchy faz aquilo. O que
-- sumiu desta lista sumiu por ter equivalente ligado no shell - a lista dos
-- motivos esta em docs/HOST-INVENTORY.md do omarchy-guest.

-- O bin/ do laboratorio na frente, para os shims (omarchy-toggle-idle e cia)
-- pegarem antes do bin/ deles. Prepend sem duplicar a entrada.
local lab_bin = (os.getenv("HOME") or "") .. "/.local/share/omarchy-lab/bin"
local caminho = {}
for entrada in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  if entrada ~= lab_bin then
    table.insert(caminho, entrada)
  end
end
table.insert(caminho, 1, lab_bin)
hl.env("PATH", table.concat(caminho, ":"))

hl.on("hyprland.start", function()
  -- Sem isto, unit de systemd que precisa do display sobe sem saber em que tela
  -- desenhar. O autostart deles nao chama (a sessao deles nao usa uwsm).
  hl.exec_cmd("command -v uwsm >/dev/null && uwsm finalize")

  -- Idle: a POLITICA continua do host. O hypridle le ~/.config/hypr/hypridle.conf,
  -- que desde 09/09 roteia o bloqueio para o lock do Omarchy. Fica aqui porque
  -- `omarchy.idle` esta desligado de proposito - o shim do Stay Awake depende
  -- de um daemon de idle que respeite systemd-inhibit.
  hl.exec_cmd(o.launch("hypridle"))

  -- O Omarchy guarda historico de clipboard enquanto roda; nao persiste o que
  -- o dono do clipboard deixou para tras. Ninguem mais faz isso.
  hl.exec_cmd(o.launch("wl-clip-persist --clipboard regular"))

  -- Parear dispositivo novo ainda passa por aqui: `omarchy.bluetooth` esta
  -- desligado nesta maquina e o widget de audio de terceiro so cuida de audio.
  hl.exec_cmd(o.launch("blueman-applet"))

  hl.exec_cmd("kdeconnect-indicator")
end)

-- O `omarchy-lab/autostart.sh` NAO entra aqui, e essa linha custou caro.
--
-- No mundo do HyDE ele era o lancador do shell do Omarchy: o autostart deles
-- nunca rodava, entao alguem tinha que chamar `omarchy-launch-shell`, e era ele
-- (com PATH e OMARCHY_PATH montados na mao, porque a sessao nao os tinha).
-- O nome "autostart.sh" faz parecer um saco de ajustes; e um `exec`.
--
-- Com o Omarchy na raiz, o `default/hypr/autostart.lua` DELES ja chama
-- `omarchy-launch-shell`. Manter a linha aqui sobe o segundo - duas barras no
-- login, que e exatamente o sintoma de 03/09 chegando por outro caminho.
--
-- Pego em 09/09 porque o teste aninhado subia dois quickshell e o Thiago viu
-- duas barras na instancia de teste. Eu tinha atribuido isso ao teste.

-- NAO estao aqui, e cada ausencia foi uma decisao:
--
--   hyprpolkitagent / polkitkdeauth  -> `omarchy.polkit` (testado em 09/09:
--                                       a caixa aparece e o agente responde)
--   wallpaper.sh --start --global    -> `omarchy.background` e o dono do fundo;
--                                       esta linha era o segundo dono que fazia
--                                       o wallpaper "voltar sozinho" no login
--   nm-applet                        -> `omarchy.network`
--   udiskie                          -> ja esta no autostart deles
--   waybar / dunst                   -> a barra e as notificacoes sao do shell
