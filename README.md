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

**Early.** Today this repo ships one thing that is worth running:

    omarchy-guest doctor

A read-only inspection of a machine that reports what would collide with a guest
install: who owns the compositor config, which bar and notification daemon are
running, whether the pieces Omarchy expects are present, and what it would try
to start that you already have.

Nothing here writes to your system yet. `doctor` only reads.

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
| lock screen has its PAM file | fresh Arch does not | one command, needs root |

## Requirements

- Arch (or a derivative) with Hyprland
- `quickshell`
- an Omarchy checkout or package for the shell itself; this project does not
  vendor it

## License

MIT
