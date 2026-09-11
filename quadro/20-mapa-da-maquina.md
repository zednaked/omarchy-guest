---
title: mapa da máquina
mode: graph
---

Lido de `omarchy-guest-graph` em 3/9/2026. Cada ponto existe nesta máquina.

```graph
group entry  #FFAA00  ponto de entrada
group host  #35C7BC  do host
group guest  #E8933A  do Omarchy
group ours  #9E92FF  nosso

[entry] HYPRLAND_CONFIG :: variable :: Decides which file Hyprland loads. Points at hyde.lua, so HyDE owns the session.
  ! The blocker for any change of ownership. Remove the host without moving this and the next login has no session.
[entry] 00-hyde.sh :: file :: Sets the variable. Uses ${VAR:-default}, so it only assigns when unset - the host yields ownership to whoever gets there first. Inverting is one file that sorts earlier, not a rewrite.
[host] hyde.lua :: file :: The real entry point. Loads the whole HyDE stack and, near the end, your own override file.
[host] ~/.config/hypr/hyprland.lua :: file :: Not the root - the override layer the entry point loads last. Editing it never changes who is in charge.
  ! Mistaking this for the entry point loads both stacks at once: two bars, duplicate keybindings, both autostarts firing.
[host] 173 keybinds :: config :: Loaded right now. Omarchy ships a comparable set, so this is a swap, not a loss - but a swap your fingers have to agree to.
[host] hypridle :: process :: Idle and screen lock. Omarchy does not cover this.
  ! Omarchy's idle/lock plugins need a PAM file a fresh Arch does not have.
[host] hyprpolkitagent :: process :: The password dialog. Omarchy does not cover this.
  ! Without one, anything asking for a password in a GUI fails silently.
[host] wl-clip-persist :: process :: Keeps the clipboard alive after the app that copied it closes. Covered on the Omarchy side by omarchy.clipboard.
[host] nm-applet :: process :: Tray icon. Omarchy has a bar widget, which is a different thing. Covered on the Omarchy side by omarchy.network.
[host] blueman-applet :: process :: Tray icon, same case as the network one. Covered on the Omarchy side by omarchy.bluetooth.
[host] hyprsunset :: process :: Colour temperature by time of day. Covered on the Omarchy side by omarchy.nightlight.
[guest] quickshell :: process :: One process drawing the bar, notifications, OSD, overlays and menu. Resident right now: 335 MB PSS. That single process is why the desktop feels consistent - and what it costs.
[guest] bar :: surface :: Replaced the host's waybar.
[guest] notifications :: surface :: Replaced the host's dunst.
[guest] menu :: surface :: Super+Space. Several of its rows overwrite config files that a guest install does not own.
[guest] bobbynicholas.omaland :: plugin :: Third-party shell plugin.
[guest] expose.window-overview :: plugin :: Third-party shell plugin.
[guest] b.okomart :: plugin :: Third-party shell plugin.
[guest] io.github.randazraik.xray :: plugin :: Third-party shell plugin.
[guest] im0001gt.hw-tooltip :: plugin :: Third-party shell plugin.
[guest] jankeesvw.downloads :: plugin :: Third-party shell plugin.
[ours] zed.updates :: plugin :: Ours - installed by omarchy-guest.
[guest] ssupt.bluetooth-audio :: plugin :: Third-party shell plugin.
[guest] ssupt.audio-control :: plugin :: Third-party shell plugin.
[ours] update engine :: code :: Vendored into omarchy-guest, so the package count works without the host installed.
[ours] menu overrides :: config :: 10 destructive row(s) hidden, and the updater swapped. Survives `omarchy update`.

HYPRLAND_CONFIG -> 00-hyde.sh
HYPRLAND_CONFIG -> hyde.lua
hyde.lua -> ~/.config/hypr/hyprland.lua
hyde.lua -> 173 keybinds
hyde.lua -> hypridle
hyde.lua -> hyprpolkitagent
hyde.lua -> wl-clip-persist
hyde.lua -> nm-applet
hyde.lua -> blueman-applet
hyde.lua -> hyprsunset
quickshell -> bar
quickshell -> notifications
quickshell -> menu
quickshell -> bobbynicholas.omaland
quickshell -> expose.window-overview
quickshell -> b.okomart
quickshell -> io.github.randazraik.xray
quickshell -> im0001gt.hw-tooltip
quickshell -> jankeesvw.downloads
quickshell -> zed.updates
quickshell -> ssupt.bluetooth-audio
quickshell -> ssupt.audio-control
menu -> menu overrides
```
