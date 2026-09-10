# Hyprland snippets

Not installed by `omarchy-guest install`, on purpose: where these belong depends
on who owns your entry point, and getting that wrong costs a session.

| file | what it is |
|---|---|
| `hyprland.lua` | the entry point with ownership inverted - Omarchy as the root, the previous owner as the fallback |
| `61-hyprland-config.conf` | the one line that makes the inversion real, for `~/.config/environment.d/` |
| `autostart.lua` | the daemons the Omarchy shell does not cover, and the list of the ones it does |
| `gaming.lua` | a performance toggle, because the host had one and Omarchy does not |

## The inversion, and the two ways it goes wrong

Editing `~/.config/hypr/hyprland.lua` does **not** invert anything. On a host
like HyDE that file is the *user override layer*, loaded near the end of the
host's own chain. Rewriting it to load Omarchy's chain gets you both stacks
alive at once - two bars, duplicated binds, duplicated daemons. That is a real
afternoon, spent here on 03/09/2026.

What inverts ownership is which file Hyprland is pointed at:

    HYPRLAND_CONFIG=/home/you/.config/hypr/hyprland.lua

It works because the host sets its own with `${HYPRLAND_CONFIG:-...}` - only if
nobody set it first. Check your host's env file before assuming this: a manager
that assigns the variable unconditionally is a harder problem.

**Where you put that line decides whether it works at all**, and this cost a
boot to learn. There are two places, and they are not equivalent:

| your session starts the compositor... | put it in |
|---|---|
| directly (a `.desktop` exec, a login shell) | `~/.config/environment.d/61-hyprland-config.conf` |
| through **uwsm** | `~/.config/uwsm/env-hyprland.d/00-guest.sh` (both files ship here) |

uwsm builds the compositor's environment by running the scripts in
`env-<compositor>.d/` in a shell that does **not** see what `environment.d`
defined, and then exports the result over the user manager's environment. So
with only the `environment.d` file, the host's `${HYPRLAND_CONFIG:-...}` still
evaluates against an empty variable and its own default wins - which is exactly
what the first boot showed. Inside uwsm's own directory the arithmetic works:
files are read in order, `00-guest` sorts before `00-hyde`, and their `:-`
preserves what is already set.

Simulate it before rebooting, instead of finding out at the login screen:

    (unset HYPRLAND_CONFIG; for f in ~/.config/uwsm/env-hyprland.d/*.sh; do . "$f"; done; echo "$HYPRLAND_CONFIG")

The second failure is quieter. `hyprctl reload` re-runs the parse but **does not
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
