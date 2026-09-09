# What the Omarchy shell assumes it owns

Written from a machine that ran the Omarchy shell as a guest for several days,
on top of another Hyprland config manager, and then tried to invert the
ownership and failed. Every item below cost something to learn. The ones marked
**only visible after a reboot** are the expensive ones: they do not show up in
`hyprctl configerrors`, they do not show up on a config reload, and the machine
looks fine right up until the next login.

None of this is a bug report. An opinionated distro is allowed to assume it owns
the machine. This is the list of what has to be true for the shell to work as a
component instead.

---

## 1. The compositor entry point

**Assumption:** Omarchy's `hyprland.lua` is what Hyprland loads, and its chain
(`bootstrap.lua` -> `default.hypr.omarchy`) runs before anything else.

**As a guest:** the host's config manager usually owns the entry point, and it
may not be the file you think. Check the environment first:

    echo "$HYPRLAND_CONFIG"

If that is set, `~/.config/hypr/hyprland.lua` is **not** the entry point - it is
an override layer that the real entry point loads near the end. Editing it can
never make Omarchy the root of the chain; it only appends Omarchy's stack to the
host's, and you end up with **both** loaded: two sets of keybindings, two bars,
and both autostarts firing.

**Cost:** this is the blocker. Everything else has a workaround.

**Shape of the fix:** it is environment-variable shaped, not code shaped.
Overriding `HYPRLAND_CONFIG` (for example in a higher-numbered
`~/.config/environment.d/` file) is what actually changes ownership. Do not test
this with `Hyprland -c <file>`: that flag ignores `HYPRLAND_CONFIG` and loads the
file you name, which is precisely the case that does not happen at login. The
only honest test is logging out.

---

## 2. The `o` helper table

**Assumption:** the global `o` exists, because their `hyprland.lua` did
`require("default.hypr.helpers")`.

**As a guest:** if their chain never ran, `o` is undefined. Anything written for
Omarchy then dies with `attempt to index a nil value (global 'o')` or
`attempt to call a nil value (field 'bind')` - **and takes down the rest of the
file with it**, because a Lua parse error stops there. A plugin that "does not
turn on" is usually this.

**Cost:** low, and no fork needed.

**Fix:** load their helpers file directly from the host's config. It is ~150
lines of pure definitions with no side effects:

```lua
local helpers = (os.getenv("OMARCHY_PATH") or "/usr/share/omarchy")
  .. "/default/hypr/helpers.lua"
local f = io.open(helpers, "r")
if f then f:close(); dofile(helpers) end
```

Loading the real file beats copying individual functions: the next `o.something`
comes for free, and their updates keep it current.

---

## 3. `OMARCHY_PATH`

**Assumption:** either the package is at `/usr/share/omarchy`, or the variable is
exported.

**As a guest:** a checkout anywhere else is invisible - their Lua falls back to
`/usr/share/omarchy` and loads nothing. Their commands also call each other by
bare name (`omarchy-menu` execs `omarchy-shell`), so `$OMARCHY_PATH/bin` has to
be on the **session** PATH, not just inside your scripts. When it is missing, a
shell restart kills the bar and cannot bring it back.

**Fix:** `~/.config/environment.d/`, so it survives host updates and transient
units inherit it.

---

## 4. Autostart: it starts a bar, and assumes nothing else did

**Assumption:** nothing is drawing a bar or handling notifications yet.

**As a guest:** the host almost certainly starts `waybar` (or ags, or eww) and
`dunst`/`mako`/`swaync`. Result: two bars, and every notification twice.

**Fix:** suppress the host's, not Omarchy's - the shell is one process for bar,
notifications, OSD and overlays, so half-disabling it is not useful. How you
suppress depends on the host.

**Suppressing the autostart is not always enough.** The daemon's package may
also ship a D-Bus service file claiming `org.freedesktop.Notifications` (on
Arch, dunst does: `org.knopwob.dunst.service`, with a static systemd user unit
behind it). Then the first `notify-send` of the boot resurrects it if it wins
the name race against the shell - no error anywhere, notifications just go to
the wrong daemon. `systemctl --user mask dunst.service` closes both paths,
because the D-Bus activation goes through systemd. `doctor` checks for this.

**Only visible after a reboot:** the reverse also bites. If you take ownership
away from the host, everything the host's session startup used to launch stops
being launched - and a config *reload* will not show it, because reload does not
re-fire the session-start event. On the machine this was written on, that was 12
systemd units. The three that hurt:

| lost | symptom |
|---|---|
| polkit agent | anything asking for a password in a GUI fails silently |
| idle daemon | no screen lock, no idle timeout |
| wallpaper daemon | no wallpaper |

**How to find yours before you reboot:**

    systemctl --user list-units --state=running > before.txt
    # ...then compare after the change

---

## 5. `uwsm finalize`

**Assumption:** not made by Omarchy at all - upstream does not launch Hyprland
through uwsm.

**As a guest:** many host setups do. In a uwsm session, the compositor's
environment (`WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE`) reaches the
systemd user manager only after `uwsm finalize`. Omarchy's autostart runs
`systemctl --user import-environment` and `dbus-update-activation-environment`,
which overlap but are not the same thing.

**Cost:** silent. Units that need the display come up without knowing which
screen to draw on.

**Fix:** whoever owns the entry point calls it once at session start.

---

## 6. The lock screen's PAM file

**Assumption:** `/etc/pam.d/omarchy-lock-password` exists, because their
installer wrote it.

**As a guest:** a machine that never ran their installer does not have it, and
the lock screen cannot authenticate.

**Fix:** `omarchy-apply-lock` writes it (needs root), or leave `omarchy.lock`
and `omarchy.idle` disabled in `shell.json` and keep the host's lock screen.
Both are fine; the second requires no root.

**Done here (09/09/2026), and the part that is not obvious:** the PAM file is
one command. What takes thought is *who calls the lock*. Enabling
`omarchy.lock` does not move the trigger: the plugin does not listen to logind,
so `SUPER+L`, the menu's Lock row and suspend all still reached the host's
locker. The trigger lives in one line of the host's idle daemon:

```ini
# ~/.config/hypr/hypridle.conf
lock_cmd = PATH="$HOME/.local/share/omarchy/bin:$PATH" omarchy-system-lock
```

`PATH` inline because their commands call each other by bare name and the idle
daemon's unit does not inherit the session `PATH` (assumption 3, in a place
nobody looks). Keeping the host's idle daemon and moving only the lock screen
is deliberate: idle policy is the host's, and the `omarchy-toggle-idle` shim
depends on it.

Two things follow for free. The Omarchy lock reads `current/background`
itself, so the lock screen follows the theme with no hook; and with nothing
else reading it, the host's wallpaper cache stopped being a dependency - see
[`THEMING.md`](THEMING.md).

Test it **before** moving the trigger: `omarchy-shell lock lock` while the
host's locker is still wired. A lock screen that cannot authenticate is only
recoverable from a TTY, at the cost of the session.

---

## 7. Theming is a second, independent system

**Assumption:** the Omarchy theme is the machine's theme.

**As a guest:** the host has its own. They do not talk to each other. The Omarchy
shell reads its palette from `~/.local/state/omarchy/current/theme`; the host
paints wallpaper, GTK, cursor and its own launcher from somewhere else. It is
entirely possible - and easy not to notice - to sit on two different themes at
once.

**Cost:** cosmetic, but it is the thing that makes a guest install feel
unfinished - and it is not one problem. The terminal, the window border, the
wallpaper, the login screen and the boot splash each miss the theme for a
different reason.

**Fix:** pick one owner and drive the other from a hook. Worked through surface
by surface, with the traps, in [`THEMING.md`](THEMING.md); `omarchy-guest-theme-apply`
and `omarchy-guest-theme-boot` implement it.

---

## 8. The installer's packages are present

**Assumption:** everything in `omarchy-base.packages` (~150 packages) got
installed, because their installer ran.

**As a guest:** on the second machine, 85 of them were absent - and that is
mostly fine, because most are desktop opinions (kdenlive, libreoffice,
obsidian, chromium) that a guest deliberately does not want. The trap is the
small subset the shell and the menu's commands invoke at runtime. The first
`omarchy plugin add` dies with `gum: command not found`; the Wi-Fi QR panel
needs `qrencode`; pasting a file from the clipboard needs `wtype`; every menu
row that opens a terminal goes through `xdg-terminal-exec` and `uwsm-app`.

**Cost:** low, but each one is discovered as a broken feature, not as an error
at install time.

**Fix:** the curated list - what actually broke, not the whole package file -
lives in `doctor` under "Runtime deps", with the `pacman -S` line ready.
85 missing packages are not 85 problems; five of them are.

---

## 9. Privileged helpers run from the packaged path

**Assumption:** helpers that need root live at `/usr/bin/omarchy-*`, and the
sudoers rules their installer wrote match those exact paths.

**As a guest:** the sudoers rule is path-exact **by design** - the grant covers
one command with one argument shape and nothing else, and that is good
security, not an oversight. But a checkout has no `/usr/bin` copy and no rule,
so the feature fails with a bare "Error accessing /usr/bin/..." on every theme
change. The browser policy write (theme color into the Chromium-family managed
policy dirs) is the first of these; the lock screen's PAM file (item 6) is the
same family of assumption.

**Cost:** one root-once command per helper, or living with the error.

**Fix:** `omarchy-guest-apply-browser-policy` installs the packaged copy, the
rule (validated with `visudo -c` first - a broken sudoers locks the whole
machine out of sudo), and the hardened policy directories, mirroring their
installer. `doctor` checks for it when a Chromium-family browser is present.

---

## 10. A managed block's "default" is the host's, not Hyprland's

**Assumption:** a config panel that owns a fenced block in
`~/.config/hypr/looknfeel.lua` writes only the keys you changed. Whatever it
leaves out falls back to Hyprland's built-in default, because on a stock install
nothing else in the chain sets those keys. The reference host's panel is
Omaland; the pattern belongs to any plugin that manages a block.

**As a guest:** the host's config manager ships an opinionated defaults layer
that runs **earlier in the chain**. A key omitted from the block does not
reveal Hyprland's default - it reveals the host's. So the panel's "put it back
to default" is not a reset: it is a handover.

Measured on the reference host (HyDE, whose
`~/.local/share/hypr/lua/defaults.lua` sets `active_opacity = 0.90` and
`inactive_opacity = 0.75`), reading one pixel inside an unfocused terminal
with a busy wallpaper behind it:

| block | `hyprctl getoption` | pixel |
|---|---|---|
| `inactive_opacity = 0.57` | 0.57 | `99 35 39` - wallpaper coming through |
| `inactive_opacity = 1` | 1.00 | `24 26 31` - the terminal's own background |
| **key removed** | **0.75** | `67 32 36` - translucent again |

The failure is silent and self-consistent. The panel re-reads its own block, so
it shows the row as "default" and agrees with itself; `hyprctl configerrors` is
empty; nothing appears in the log. Only `hyprctl getoption` disagrees. The user
symptom is "I set the slider to the maximum and the window is still
see-through", which reads as "the panel does not save" and is not.

**Cost:** high in wasted time, low to fix. Diagnosing it means suspecting the
panel first, and the panel is innocent.

**Fix:** never leave a row "at default" through the panel on a guest. If the
value you want happens to equal the stock default, write the key explicitly
anyway so the block keeps asserting it over the host's layer. It generalises to
everything the host's defaults file touches, not just opacity.

Diagnostic worth keeping - compare every key in the block against what the
compositor actually holds, since the two are supposed to be identical:

    hyprctl getoption decoration:inactive_opacity

To measure blending without trusting your eye, sample a single pixel:

    grim -g "<x>,<y> 1x1" -t ppm - | tail -c 3 | od -An -tu1

### The second trap in the same family: `opacity` multiplies, `opaque` overrides

Hyprland's `opacity` **window rule** is a multiplier on the
`decoration:*_opacity` globals, not an override. A rule of `opacity = "1 1"`
multiplies by one and changes nothing - no error, no log line, no pixel moved.
The rule that actually forces a window solid is `opaque = true`.

This matters as a guest because Omaland's **Full opacity** switch is the one
control that writes outside `looknfeel.lua`: it appends
`o.window(".*", { opacity = "1 1" })` to `hyprland.lua`. On a stock install that
cancels Omarchy's own blanket `opacity "0.985 0.96"` from
`default/hypr/windows.lua`. On a guest that blanket rule never loads, so the
switch multiplies nothing by one and is **inert** - and, worse, it teaches the
idiom, so the same `opacity = "1 1"` gets copied into a hand-written rule meant
to force a window opaque, where it is equally inert. Omaland's own
`Schema.js` says so plainly ("That rule multiplies with the globals below"); it
is easy to read as an override and lose an afternoon.

---

## Things that are NOT a problem

Worth stating, because they are the usual worries:

- **The shell runs standalone.** One `quickshell` process, no distro pieces
  required beyond a theme state directory and its `bin/` on PATH.
- **Plugins hot-reload as a guest.** Saving under `~/.config/omarchy/plugins/`
  reloads plugin code normally. (Caveat: a widget already instantiated in the
  bar keeps its old property values; `omarchy restart shell` is what applies
  those.)
- **It is well-behaved on disk.** On the reference machine it touched four
  directories under `$HOME` and exactly one file outside it.
