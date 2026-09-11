# The half that lives outside `$HOME`

Everything else in this repo is user-level and reversible by deleting a folder.
This directory is not: it is the identity that shows up **before you log in**,
and all of it needs root.

    omarchy-guest system --dry-run    # prints every sudo it would run
    omarchy-guest system

| piece | goes to | shows up |
|---|---|---|
| `plymouth/zednet/` | `/usr/share/plymouth/themes/zednet` | next **boot** |
| `sddm/theme.conf` | `/etc/sddm.conf.d/50-omarchy-guest.conf` | next **logout** |
| `issue` | `/etc/issue` | next TTY |
| `fastfetch/` | `~/.config/fastfetch/` (user-level, installed by `install`) | next shell |

Everything replaced is copied first to
`~/.local/state/omarchy-guest/backups/system/<timestamp>/`.

## Why it is a separate subcommand

`install` writes only inside `$HOME` and never asks for sudo. Someone who wants
the shell, the plugins and the config but not our splash screen runs `install`
and stops. Keeping the two apart is what makes that a real choice instead of a
diff to read.

## The plymouth theme is not just files

`plymouth-set-default-theme -R` is the part that matters: the theme actually
lives in the initramfs, and copying into `/usr/share` without regenerating it
leaves the old splash on screen with the new theme on disk. The installer always
passes `-R`.

## sddm: one file, and why the warning matters

`/etc/sddm.conf.d/` is read in order and the **last** `Current=` wins. A machine
that has been through a config manager usually has two or three files there,
each convinced it owns the theme; which one wins is alphabetical accident.

`omarchy-guest system` writes exactly one file and, before writing, tells you
whether anything in that directory beats it — by name comparison, not by guess.
If something does, it says so plainly: ours will have no effect until those are
removed. On a flavor machine there are no competitors and the question does not
arise; on a machine still carrying a host, it always does.

The theme named in `theme.conf` has to be installed separately - it is a package,
not something this repo vendors. The installer checks and warns if the directory
is not there.
