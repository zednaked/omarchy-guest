# Theming a guest install

On a machine Omarchy installed, one theme paints everything. On a guest install
there are two theme systems that do not know about each other, and the seam is
the most visible thing about the setup: you switch the Omarchy theme, the bar
changes, and the terminal, the window borders, the wallpaper, the login screen
and the boot splash stay where they were.

This is what reaches each surface, what does not, and why.

## What the Omarchy theme reaches on its own

The shell - bar, notifications, overlays, menu, OSD - because that is one
process reading one palette. Plus every file its theme ships that it is
*allowed* to install: gtk, btop, neovim, vscode, and so on.

## What it does not reach, and why each one is different

The causes are not the same, which is why fixing one does not fix the others.

### The terminal - a refusal, and a missing reload

A theme ships a whole `kitty.conf`, and `omarchy theme set` **refuses to install
it**: the file is in that command's `INSTALLED_THEME_DENIED` list, along with
`alacritty.toml`, `foot.ini`, `ghostty.conf` and `vscode.json`. That refusal is
correct - the theme's file is a full configuration, not a palette, and copying
it over yours would take your font, padding and keybindings with it.

So the colours arrive on the machine and nothing consumes them. The fix is to
extract only the colour keys into the file kitty already includes.

And then a second half that is easy to miss: **writing the file changes nothing
in a terminal that is already open.** Kitty re-reads its configuration on
`SIGUSR1`. Without that, the fix looks like it did not work, because every
window you are looking at is still on the old palette.

**Which side wins is decided by include order.** On the reference machine:

    kitty.conf:1    include hyde.conf        ->  which includes the host's theme.conf
    kitty.conf:26   include current-theme.conf   <- Omarchy's

Kitty applies includes in order and the last definition wins, so Omarchy wins.
Neither project rewrites `kitty.conf` - the host's own header says to put custom
configuration there, and Omarchy denies it - so the order is the user's and
stays put. It is still worth a comment at the point of danger: the failure is
"the colour is wrong" and the cause is "include order", and those two do not
look like each other.

### The window border - ownership, and a gradient that is not a colour

The host's theme sets `general.col.active_border`, and the Omarchy theme does
not touch it. Load order decides again: a file loaded after the host's theme
wins, and the user's `looknfeel` is loaded near the end of the chain, so that is
where the override goes.

**The kitty colours are an orphan the same way.** `current-theme.conf` is only
a theme if something includes it, and a host's kitty config has its own include
chain that has never heard of ours. On the second machine the colours were
"applied" for a day into a file kitty never read - no error, the terminal just
kept the host's palette. `theme-apply` now appends the include to `kitty.conf`
itself when it is missing, at the end, where the last definition wins.

**On a guest, `looknfeel.lua` is an orphan until you wire it.** Omarchy's own
chain loads `~/.config/hypr/looknfeel.lua`; the host's chain has never heard of
it. Anything that writes there - the Omaland panel does exactly that - edits a
file nothing reads, with a failure mode built to confuse: Omaland previews via
`hyprctl eval` (in memory, instant) and saves via write + `hyprctl reload`, and
the reload re-runs a chain without the file, discarding the preview you just
watched work. "I changed it and nothing changed" is this. The fix is two
`dofile`s at the end of the user's `hyprland.lua`, in this order: `looknfeel.lua`
first, then `hypr-theme.lua` from this project's state dir - which also fixes
the themed border quietly resetting at login, since before this it was only
ever applied live by the theme-set hook. And whatever restores a "normal" look
by hand - the gaming toggle here does - must re-run those two files rather than
trust frozen values.

Three traps, in the order they bite:

**1. The theme declares the border, so do not derive it.** `shell.toml` has a
`[hyprland]` section naming exactly what it wants. Deriving from `accent` and
`foreground` happens to match on some themes and is wrong on any theme that
chose otherwise.

**2. It declares a gradient, not a colour.** Up to ten stops and an angle:

    active-border = "#ad2222 #ad2222 #ad2222 #ad2222 #eceff2 ... 35deg"

Reading the first hex - which is what a plain key lookup gives you - throws away
the highlight stop and the angle and paints a flat border. Take the whole line.

**3. In Lua, a gradient is a table.** The string form that works in
`hyprland.conf`:

```lua
-- rejected: invalid color
col.active_border = "rgba(ad2222ff) rgba(eceff2ff) 35deg"

-- accepted
general = { col = { active_border = {colors = {"rgba(ad2222ff)", "rgba(eceff2ff)"}, angle = 35} } }
```

And do not carry the `#` into `rgba()` - `rgba(#ad2222ff)` fails the same way,
and one bad stop drops the whole gradient.

**Applying it live needs `eval`, not `keyword`.** With the Lua parser,
`hyprctl keyword` answers *"keyword can't work with non-legacy parsers. Use
eval."* Send that to `/dev/null` and it fails silently: the generated file is
correct, the live value never moves, and it only appears to work because
something else reloads later.

### The wallpaper - the host's daemon owns the screen

Omarchy records which image its theme wants, in `current/background`. On a guest
install the host's wallpaper daemon is what actually paints. Pointing the host
at Omarchy's choice keeps one daemon and makes the wallpaper follow the theme;
enabling Omarchy's own background plugin instead means turning the host's off,
or having two.

### The boot splash and the login screen - literals, root, and the initramfs

A Plymouth theme and an SDDM theme carry their colours as literals in a script
and a conf. Nothing rewrites them on a theme change, so the machine ends up
consistent from the desktop up and stuck on whatever palette the boot chain was
built with.

Two costs the desktop surfaces do not have:

- **Root**, because both live under `/usr/share`.
- **The initramfs.** A Plymouth theme is *inside* it. Editing the files on disk
  without `mkinitcpio -P` changes nothing at boot - and that failure looks
  exactly like "it did not work", with no error to point at the cause.

That is why these two are a manual command and not part of the theme-set hook: a
hook that asks for a password, or blocks for a minute in the middle of switching
theme, is worse than the inconsistency it fixes.

**Repaint all of it or none of it.** The first pass here did the background, the
text and the progress bar and left the logo on its original blue. That is worse
than not having started: before, the splash was coherent in one palette; halfway
through, it was a mix.

## The two commands

```bash
omarchy-guest-theme-apply    # border, terminal, wallpaper - instant, no root
omarchy-guest-theme-boot     # splash and login - root, rebuilds the initramfs
```

`theme-apply` is what the `theme-set` hook runs, so those three follow every
theme change on their own. `theme-boot` takes `--dry-run`, `--no-initramfs` and
`--restore`, and keeps pristine copies under
`$XDG_STATE_HOME/omarchy-guest/boot-theme-orig/`.

Those copies are taken **once**, on the first run. Re-copying would capture an
already-repainted file as the "original" and turn `--restore` into a no-op -
the quiet way a restore path stops working.

## The general shape

Every one of these is the same problem wearing different clothes: **two systems,
one screen, and load order deciding who wins.** Where the order already favours
the theme you want, document it at the point where someone might reorder it.
Where it does not, add a file that loads last. Where neither side reads a
palette at all, generate the literals and regenerate them on a hook.
