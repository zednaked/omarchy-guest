# Hyprland snippets

Not installed by `omarchy-guest install`, on purpose: where these belong depends
on who owns your entry point, and getting that wrong costs a session.

| file | what it is |
|---|---|
| `hyprland.lua` | the entry point with ownership inverted - Omarchy as the root, the previous owner as the fallback |
| `61-hyprland-config.conf` | the one line that makes the inversion real, for `~/.config/environment.d/` |
| `00-guest.sh` | the same line for `~/.config/uwsm/env-hyprland.d/`, when the host **yields** the variable |
| `99-guest.sh` | the same line for the same directory, when the host **does not** - it sorts last instead of first |
| `rebind.lua` | `o.rebind` for an Omarchy that does not ship one - lets a file of yours replace a bind of theirs instead of stacking on it |
| `cursor.lua` | the cursor theme at **login** - a host that exported `XCURSOR_THEME` takes it with it, and the theme hook only fixes it until the next boot |
| `autostart.lua` | the daemons the Omarchy shell does not cover, and the list of the ones it does |
| `gaming.lua` | a performance toggle, because the host had one and Omarchy does not |
| `bindings.lua` | window-manipulation defaults a guest expects: `SUPER + W` floats instead of being a second close key, `SUPER + P` screenshots, and border resize actually switched on |

## `bind` adds, `rebind` replaces

Binding a key Omarchy already uses with `o.bind` does not override it - both
actions fire on the same gesture, `hyprctl binds` lists the key twice, and
nothing is logged. Use `o.rebind` for any key that is already taken, and check
first:

    omarchy menu keybindings --print
    hyprctl binds -j | jq -r '.[] | select(.modmask==64) | .key' | sort | uniq -d

Two Omarchy defaults are worth knowing about here: `SUPER + W` and `SUPER + Q`
are bound to the *same* `close window`, and `SUPER + P` is `pseudo window`.

**`o.rebind` may not exist on your Omarchy.** It is not in `helpers.lua` on the
second machine's checkout, and `o.bind` there throws the return value of
`hl.bind` away - which is the object carrying `:unbind()`, the only handle on a
bind someone else created. So a file of yours loaded later has nothing to
release, and `bindings.lua` in this directory would die on the call.

`rebind.lua` here fills that in: required **before** Omarchy's chain, it wraps
`hl.bind` and keeps every object by combo, so `rebind()` can release theirs and
put yours in its place. Where `o.rebind` already exists, it wins and this file
is dead weight - requiring it anyway costs nothing and keeps one config working
on both.

## The setting that looks enabled and is not

`extend_border_grab_area` defaults to 15 while `resize_on_border` defaults to
**false**. Reading the first one makes border resize look configured; dragging a
corner does nothing. Raising `border_size` does not fix it - the grab area is
invisible and 15px wide either way, and a zero-width border is not the problem.

## The inversion, and the three ways it goes wrong

Editing `~/.config/hypr/hyprland.lua` does **not** invert anything. On a host
like HyDE that file is the *user override layer*, loaded near the end of the
host's own chain. Rewriting it to load Omarchy's chain gets you both stacks
alive at once - two bars, duplicated binds, duplicated daemons. That is a real
afternoon, spent here on 03/09/2026.

What inverts ownership is which file Hyprland is pointed at:

    HYPRLAND_CONFIG=/home/you/.config/hypr/hyprland.lua

On a host that sets its own with `${HYPRLAND_CONFIG:-...}` this works because
`:-` means *only if nobody set it first*. **Check the effect, not the text.**
A host can declare the `:-` and still overwrite you, and HyDE is the worked
example: its env file has the `:-`, but it first sources
`~/.local/lib/hyde/shell/activate`, and that file opens with
`HYPRLAND_CONFIG=""`. By the time the `:-` is evaluated your value is gone, so
the host's default always wins. Measured on the second machine on 16/09/2026,
with `00-guest.sh` already installed and the boot still on `hyde.lua`.

That is the third failure, and it has its own fix - see **the name** below.

**Where you put that line decides whether it works at all**, and this cost a
boot to learn. There are two places, and they are not equivalent:

| your session starts the compositor... | put it in |
|---|---|
| directly (a `.desktop` exec, a login shell) | `~/.config/environment.d/61-hyprland-config.conf` |
| through **uwsm** | `~/.config/uwsm/env-hyprland.d/` - and there the *name* is a second decision, below |

uwsm builds the compositor's environment by running the scripts in
`env-<compositor>.d/` in a shell that does **not** see what `environment.d`
defined, and then exports the result over the user manager's environment. So
with only the `environment.d` file, the host's `${HYPRLAND_CONFIG:-...}` still
evaluates against an empty variable and its own default wins - which is exactly
what the first boot showed.

### And then the name, which is the third failure

Inside uwsm's own directory the files are read in order, so the name decides who
has the last word. Which end you want depends on the host:

| the host... | install | because |
|---|---|---|
| yields (`${VAR:-default}`, and nothing wipes it earlier) | `00-guest.sh` | sorts **before** the host, and its `:-` preserves you |
| overwrites (assigns, or wipes in a sourced script) | `99-guest.sh` | sorts **after** the host, so yours is the last assignment |

Both ship here and you install one.

**Simulate it before rebooting**, instead of finding out at the login screen -
one line answers which case you are in:

    (unset HYPRLAND_CONFIG HYDE_ACTIVATED
     for f in ~/.config/uwsm/env-hyprland.d/*.sh; do . "$f"; done
     echo "$HYPRLAND_CONFIG")

The `unset HYDE_ACTIVATED` is what makes it faithful: HyDE's `activate` returns
early when that is set, so without the unset you simulate a login that never
happens and get the answer you wanted to see. Whatever your host's equivalent
guard is, clear it too.

The last failure is quieter. `hyprctl reload` re-runs the parse but **does not
fire `hyprland.start`**, so every autostart from the old session is still
running and the inversion looks complete when it is not. The next login is what
tells the truth, and what it tells is that daemons nobody starts any more are
simply gone - the lock dialog, the wallpaper, the polkit prompt. Compare
`systemctl --user list-units` before and after; that diff is your autostart file.

## The fallback is the point

`hyprland.lua` here has two roles. As the root it loads Omarchy's chain. Loaded
*by* the old host's chain - which is what happens if the env override does not
take - it detects that and hands control back to the old override layer instead
of stacking. So a login where the variable did not arrive comes up exactly like
yesterday, instead of doubled. If everything looks like it did before the
inversion, the symptom is not "it failed": check `echo $HYPRLAND_CONFIG`.
