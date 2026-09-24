# omarchy-guest

Run the [Omarchy](https://omarchy.org/) shell as a **guest** on an Arch machine
you already set up, instead of letting it own the machine.

Omarchy is installed by a script that takes the disk and the bootloader. That is
a deliberate choice for an opinionated distro, and it works. But it means the
shell - the bar, the menu, the overlays, and the
[2000+ community plugins](https://omarchyplugins.com/) around them - is only
reachable if you were willing to reinstall.

This project is about the other path: keeping your compositor config, your
keybindings and your theming exactly where they are, and letting the Omarchy
shell run on top of them.

## Status

Running as the daily shell on two machines - the reference machine and a
second install that found (and fixed) everything machine-specific the first
one could not see - and on a third with **no host at all**: a plain Arch
install with only the shell on top, written up in
[`docs/NO-HOST.md`](docs/NO-HOST.md) and packaged as an installer in
[omarchy-zero](https://github.com/zednaked/omarchy-zero).

    omarchy-guest doctor              # read-only inspection, changes nothing
    omarchy-guest-contract --ref origin/quattro --commits   # what their next update breaks
    omarchy-guest install --dry-run   # show what would be written
    omarchy-guest install             # copy plugins and menu overrides into place

`doctor` reports what would collide with a guest install: who owns the compositor
config, which bar and notification daemon are running, whether the pieces Omarchy
expects are present, and what its autostart would launch on top of what you
already run.

`install` copies this repo's pieces into `~/.config/omarchy/`, backing up every
destination with a timestamp first. It copies rather than symlinks on purpose:
the shell scans and watches the plugin directory, and a symlinked tree is one
more thing that can behave differently on a machine you are not sitting at.

## Layout

    bin/            the CLI
    contract/       the inferred contract with upstream, and the verified ref
    docs/           the maps - read these first
    plugins/        Omarchy shell plugins that make sense on a guest install
    extensions/     menu overrides (what to hide, what to replace)
    hypr/           Hyprland snippets, NOT installed automatically
    hooks/          theme-set hook, installed into ~/.config/omarchy/hooks/
    quadro/         starter documents for the board
    vendor/         third-party code, with its own licence (see its NOTICE)
    lib/            the `o` helper shim
    shims/          same-named wrappers around Omarchy commands, PATH-first

## Why this is not the same as "install Omarchy without wiping my disk"

There is an open request upstream for an overlay installer
([issue #2208](https://github.com/omacom/omarchy/issues/2208),
[discussion #2209](https://github.com/omacom/omarchy/discussions/2209)). That
one is about partitions and bootloaders.

This is a different problem, and the harder half: **Omarchy assumes it owns the
compositor's entry point.** Its Hyprland config is a chain rooted in its own
`hyprland.lua`, its helper table `o` is only defined if that chain ran, and its
autostart assumes nothing else already started a bar, a notification daemon or
an idle daemon.

None of that is a bug. It is what an opinionated distro is allowed to assume.
It just makes the shell unusable as a component, and that is what this project
tries to fix from the outside, without a fork.

## Documents

- [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) - every place the shell assumes it
  owns the machine, what breaks when it does not, and the cost.
- [`docs/MENU-OVERRIDES.md`](docs/MENU-OVERRIDES.md) - the menu rows that
  overwrite user config, and the supported way to disable or replace them so the
  change survives `omarchy update`.
- [`docs/HOST-SURVEY.md`](docs/HOST-SURVEY.md) - how to take this inventory on
  your own machine, whatever your host is. Five questions, the commands that
  answer each from the running system, and the traps that make a reading wrong.
- [`docs/HOST-INVENTORY.md`](docs/HOST-INVENTORY.md) - what still comes from the
  host, what is load-bearing, and the order that makes removing it possible.
  The reference machine's answers, and the worked example for the survey.
- [`docs/THEMING.md`](docs/THEMING.md) - which surfaces the Omarchy theme reaches
  by itself, which it does not and why each one is different, and the traps that
  make a theme change look like it half worked.
- [`docs/UPSTREAM-CONTRACT.md`](docs/UPSTREAM-CONTRACT.md) - everything the guest
  depends on inside Omarchy, written as assertions that run against a ref
  before the update lands, and the workflow around them.
- [`docs/QUADRO-FORMAT.md`](docs/QUADRO-FORMAT.md) - the board document format.

## What we already know

The map is in [`docs/ASSUMPTIONS.md`](docs/ASSUMPTIONS.md): every place the
Omarchy shell assumes ownership, what breaks when the assumption does not hold,
and which of them have a cheap workaround. It was written from a machine that
ran the shell as a guest for days on top of another Hyprland config manager -
including the parts that only show up after a reboot, which is where this gets
expensive to learn.

Short version:

| assumption | reality as a guest | cost |
|---|---|---|
| owns `hyprland.lua` | host's config manager owns it | the blocker; env-var shaped |
| helper table `o` is global | only exists if their chain ran | one `dofile`, no fork |
| its autostart starts the bar | host may already run one | two bars |
| nothing else runs a notification daemon | host usually does | duplicate notifications |
| lock screen has its PAM file | fresh Arch does not | one command, needs root - but the trigger stays with the host until you move it |
| nothing else claims the notifications D-Bus name | the daemon's package dbus-activates it at boot | one user-unit mask |
| the installer's ~150 packages are present | only what the shell calls matters | five packages; doctor lists them |
| privileged helpers live in `/usr/bin` | a checkout has no packaged path | one root-once apply command |
| a key left out of a panel's block falls back to Hyprland's default | it falls back to the host's defaults layer | silent; the panel agrees with itself |

## What ships here

- **`zed.updates`** - a bar widget with a package count per source. Omarchy's
  own updater reports no inventory, so this borrows the host's engine. See
  [`docs/HOST-INVENTORY.md`](docs/HOST-INVENTORY.md) for why decoupling it is
  next.
- **Menu overrides** - hiding the rows that overwrite config a guest does not
  own, and swapping the updater. See
  [`docs/MENU-OVERRIDES.md`](docs/MENU-OVERRIDES.md).
- **`hypr/gaming.lua`** - a performance toggle, because the host had one and
  Omarchy does not.
- **`zed.quadro`** - a board of Markdown documents, rendered as force-directed
  graphs or prose. A folder of `.md` files, one tab each; drop a file in and it
  becomes a tab. Format in [`docs/QUADRO-FORMAT.md`](docs/QUADRO-FORMAT.md).
- **`zed.ganja`** - **moved out of this repo** on 2026-09-12, to
  [github.com/zednaked/omarchy-ganja](https://github.com/zednaked/omarchy-ganja),
  because it is being submitted to the Omarchy plugin marketplace and that needs
  a repo of its own with the manifest at the root. Install it with
  `omarchy plugin add https://github.com/zednaked/omarchy-ganja --enable`, and
  update it with `omarchy plugin update zed.ganja`.

  Keeping a copy here too was the obvious thing and the wrong one: two copies of
  the same QML diverge, and the one that gets edited is never the one that gets
  installed.

  (What it is: a cannabis plant that grows in the bar, a QML port of
  [Ganja-TUI](https://github.com/zednaked/Ganja-TUI) - same 35 strains, same
  procedural 70x28 ASCII art, same save format, no Rust binary and no resident
  process. Closed it costs one 60-second timer; stopped, nothing at all.)
- **`omarchy-guest-contract`** - checks this repo against any Omarchy ref
  without touching the installed checkout: their commands we call, the menu ids
  we override, the QML the plugins read off the third-party facade, the lists we
  copy. The verdict is differential against the ref in `contract/verified`, so a
  note that rotted is not reported as a regression. See
  [`docs/UPSTREAM-CONTRACT.md`](docs/UPSTREAM-CONTRACT.md).
- **`omarchy-guest-graph`** - reads the running machine and emits its ownership
  graph as JSON. Read-only; the board's machine map is generated from it.
- **`omarchy-guest-theme-apply`** - makes the window border and the terminal
  follow the Omarchy theme, plus the wallpaper on a host that still paints it.
  Instant, no root; wired to a `theme-set` hook so it runs on every theme
  change. Where `omarchy.background` is enabled it leaves the wallpaper alone -
  the shell reads the theme's background itself, and a hook that repaints is
  just a second owner.
- **`omarchy-guest-theme-boot`** - the same for the boot splash and the login
  screen. Needs root and rebuilds the initramfs, so it stays a manual command,
  with `--dry-run`, `--no-initramfs` and `--restore`.
- **`omarchy-guest-apply-browser-policy`** - the root half of themed browser
  colors, once per machine: packaged path, sudoers rule (validated before it
  counts), hardened policy dirs. See ASSUMPTIONS item 9.
- **`shims/`** - scripts named like an Omarchy command that wrap the original
  instead of replacing it, placed ahead of their `bin/` by `omarchy-guest-run`.
  First one: `omarchy-toggle-idle`, so Stay Awake holds a systemd idle
  inhibitor the host's idle daemon respects. See
  [`docs/MENU-OVERRIDES.md`](docs/MENU-OVERRIDES.md).
- **`omarchy-guest-run`** and **`omarchy-guest-launch-shell`** - environment
  wrappers. Omarchy's commands call each other by bare name, and the compositor
  that was already running when the guest was installed does not have their
  `bin/` on PATH until the next login. `run` wraps any of their commands;
  `launch-shell` is what the host's autostart calls on `hyprland.start`.

## Requirements

- Arch (or a derivative) with Hyprland
- `quickshell`
- an Omarchy checkout or package for the shell itself; this project does not
  vendor it

The shell reads its palette from `~/.local/state/omarchy/current/theme`. On a
machine that never ran Omarchy, populate it without touching the live session:

    OMARCHY_THEME_HEADLESS=1 omarchy-theme-set tokyo-night

## License

MIT
