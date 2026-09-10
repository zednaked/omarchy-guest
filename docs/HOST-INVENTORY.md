# What still comes from the host

A guest install is not a migration. Some things keep coming from the host config
manager, on purpose, and some are just not ported yet. Telling the two apart is
the difference between "we can remove the host now" and "removing the host costs
us a session".

This is the inventory from the reference machine, where the host is
[HyDE](https://github.com/HyDE-Project/HyDE). The *shape* of the list transfers
to any host; the specific commands do not.

Method: read from the running system (`systemctl --user list-units`,
`hyprctl binds`, the config chain), not from memory. Re-run it after any change
of ownership.

---

## Load-bearing: removing the host breaks these today

### 1. The compositor entry point

    HYPRLAND_CONFIG=<host>/hyde.lua

Set by `~/.config/uwsm/env-hyprland.d/00-hyde.sh`. Everything the compositor
loads is rooted there. **Remove the host without moving this first and the next
login has no session.**

The one piece of good news in the whole inventory is how that file sets it:

```sh
HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-.../hyde.lua}"
```

`:-` means *only if unset*. The host yields ownership to whoever set the variable
first. So inverting ownership is a small file in the same directory that sorts
earlier - not a rewrite of anyone's config. This is worth checking on your own
host before assuming the worst: a manager that hardcodes the assignment is a much
harder problem than one that defaults it.

### 2. Keybindings

173 bindings, all of them the host's. By category: 80 workspaces, 34 window
management, 17 launcher, 14 hardware controls, 11 utilities, 9 theming.

Omarchy ships a comparable set, so this is a swap rather than a loss - but it is
a swap your fingers have to agree to. Porting all 173 to discover you use 15 is
wasted work; the honest move is to live on the other map for a few days and port
what you reach for and miss.

### 3. Session daemons

The host's session start launches these; Omarchy's autostart does not.

| unit | process | covered by Omarchy? | state here |
|---|---|---|---|
| `*-idle` | hypridle | partially - the lock screen moved to `omarchy.lock` (09/09/2026); idle policy stays the host's, and the `omarchy-toggle-idle` shim depends on it | **kept** |
| polkit agent | polkitkdeauth.sh | yes - `omarchy.polkit` | stopped 09/09 |
| `*-wallpaper` | wallpaper.sh | yes - `omarchy.background` owns the wallpaper and the host's service is off in the host config; nothing reads the host's wallpaper cache any more | stopped 03/09 |
| `*-clipboard-persist` | wl-clip-persist | no - Omarchy keeps history, not persistence | **kept** |
| `*-network-manager-applet` | nm-applet | yes - `omarchy.network` | stopped 09/09 |
| `*-bluetooth-applet` | blueman-applet | partially - `omarchy.bluetooth` is off here and the third-party audio widget only does audio; pairing still goes through blueman | **kept** |
| `*-battery-notify` | batterynotify.lua | yes - `omarchy.battery` | stopped 09/09 |
| `*-blue-light-filter` | hyprsunset | yes - `omarchy.nightlight`, which spawns the binary itself when a temperature is asked for | stopped 09/09 |
| `*-text-clipboard`, `*-image-clipboard` | wl-paste watchers | yes - `omarchy.clipboard` | stopped 09/09 |
| `*-removable-media-applet` | udiskie | yes - it is in their autostart too, but here the host's copy is the one running | **kept** |
| `*-config-watcher` | config.lua | host-only, no loss | stopped 09/09 |

Eleven of these were running **at the same time as the Omarchy plugin that
covers them**: two battery notifiers, two clipboard histories, two polkit
agents. Nothing announced it - a second polkit agent is not an error, it just
means whoever claimed the name first is the one answering. The audit that found
it is one command:

    omarchy-shell shell listPlugins        # what the shell already covers
    systemctl --user list-units --state=running | grep hyde-

Turning them off is a line each in the host's config
(`hyde.config.start.<field> = nil`, the same mechanism that already retired the
bar and the notification daemon) plus `systemctl --user stop` for the running
copy. Reversible by uncommenting and logging in again.

**Beware a contaminated reading.** This list is only accurate on a normal boot.
On the reference machine, `waybar` and `dunst` are suppressed by two lines in the
host config; after a boot where those lines were missing, both came back and the
inventory showed them as "running", which is true and misleading. Check *why*
something is running before recording it as a dependency.

### 4. The package updater

`system.update.py` + `pm.py` in the host's lib directory. This one is load-bearing
by our own doing: the bar widget and the menu's replaced "System" row both call
it (see [`MENU-OVERRIDES.md`](MENU-OVERRIDES.md)).

**It is also the easiest to decouple.** 267 + 630 lines of Python importing
nothing but the standard library. Copying both out makes the widget a standalone
component and removes the dependency entirely. Omarchy has no equivalent - its
own updater reports no inventory - so this is a genuine gap worth filling in this
project rather than borrowing forever.

### 5. Theming and wallpaper

The host drives wallpaper, GTK, cursor and its own launcher from its theme
pipeline; Omarchy's shell reads its own palette. Two systems, no link between
them, and they drift: on the reference machine they sat on different themes for
days without anyone noticing.

Not load-bearing in the "breaks the session" sense. Load-bearing in the "the
desktop stops looking coherent" sense, which is why a guest install feels
unfinished before this is decided.

**Decided, on the reference machine:** the Omarchy theme owns the look and the
host is driven from a `theme-set` hook. Surface by surface, with the traps, in
[`THEMING.md`](THEMING.md).

The wallpaper came off that hook on 09/09/2026: `omarchy.background` paints it
and reads `current/background` itself. What made the difference was not the
painting - it was that the host's daemon remembers its own wallpaper and
reapplies it at session start, so a hook that repaints on every theme change
still loses the next login.

---

## Not load-bearing: already replaced, or never used

- **Bar and notification daemon.** The Omarchy shell replaces both. On this
  machine the host's are suppressed by config, not uninstalled.
- **Workflows / performance mode.** The host's "gaming" workflow is eight lines
  of `hl.config`; a replacement lives in the reference machine's config and does
  not need the host at all.
- **The host's own config watcher and menu.** Superseded by the Omarchy menu.

---

## Order that makes removal possible

Each step is independently reversible. Do not skip to the end.

1. **Invert the entry point** through the host's env file, and test **by logging
   out**. A config reload does not re-fire session start, so it cannot show you
   what a login will do.
2. **Port the keybindings you actually miss**, after living on Omarchy's map.
3. **Decouple the updater** into this project.
4. **Turn off the daemons Omarchy already covers**, then replace the ones it
   does not. The lock screen
   is done: `omarchy-apply-lock` writes the PAM file, `omarchy.lock` gets
   enabled, and the host's idle daemon routes to it through one `lock_cmd`
   line - see [`ASSUMPTIONS.md`](ASSUMPTIONS.md) item 6, including why enabling
   the plugin alone does not move the trigger.
5. **Pick one theme owner** and drive the other from a hook - see
   [`THEMING.md`](THEMING.md), which is this step done.
6. Only then consider removing the host - and even then, the host being on disk
   costs nothing.
