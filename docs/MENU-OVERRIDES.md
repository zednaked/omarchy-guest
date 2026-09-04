# Making the Omarchy menu safe on a machine it does not own

The Omarchy menu (`Super+Space`) is built for a machine Omarchy installed. A
handful of its rows overwrite configuration files with Omarchy defaults. On a
guest install those files belong to someone else, and the rows are destructive.

This is the list, and the supported way to disable them.

## The override point

    ~/.config/omarchy/extensions/omarchy-menu.jsonc

Reusing an existing id overrides that row; `when` is a shell condition and the
row disappears when it fails, so `"when": "false"` hides a row permanently.

**This file survives `omarchy update`.** Verified on Omarchy as of 2026-09: no
migration under `migrations/` references `extensions`, and `omarchy-update` does
not write inside `~/.config/omarchy`. Editing
`$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` instead would work today and
be silently reverted on their next update - the exact failure mode this project
exists to document.

Changes take effect after `omarchy restart shell`. Saving alone is not enough:
the shell re-reads plugin code on save, but menu rows already built keep their
old definition.

## Rows that overwrite user config

Check each against your host before deciding. The command behind every one of
them is readable with `cat $(which <command>)`.

| row id | command | what it overwrites |
|---|---|---|
| `update.config.hyprland` | `omarchy-refresh-hyprland` | `~/.config/hypr/`: `hyprland.lua`, `monitors.lua`, `looknfeel.lua`, `autostart.lua`, `bindings.lua`, `input.lua` |
| `update.config.shell` | `omarchy-refresh-shell` | `~/.config/omarchy/shell.json` **and** runs `omarchy-bar defaults` - your bar layout and plugin list |
| `update.config.plymouth` | `omarchy-refresh-plymouth` | the Plymouth boot theme |
| `style.unlock` | `omarchy-plymouth-reset` | Plymouth **and** the SDDM login theme (`omarchy-refresh-sddm`) |
| `update.config.hyprsunset` | `omarchy-refresh-hyprsunset` | `~/.config/hypr/hyprsunset.conf` |
| `setup.reset` | `omarchy-system-factory-reset` | the machine (btrfs roots only) |

`update.config.hyprland` is the dangerous one. On a guest install
`~/.config/hypr/hyprland.lua` is usually not Omarchy's - it is the host's config,
or the host's user-override layer. Overwriting it does not show an error: the
session keeps running on the config already in memory, and breaks at the next
login.

Hiding beats renaming. The menu has fuzzy search, so a quickly typed "config"
plus Enter is enough to fire a row you meant to avoid.

## Example

```jsonc
{
  // Destructive on a guest install - see docs/MENU-OVERRIDES.md
  "update.config.hyprland":  { "when": "false" },
  "update.config.shell":     { "when": "false" },
  "update.config.plymouth":  { "when": "false" },
  "update.config.hyprsunset":{ "when": "false" },
  "style.unlock":            { "when": "false" },
  "setup.reset":             { "when": "false" }
}
```

Leave in whatever is genuinely absent on your machine. `update.config.tmux`, for
instance, is harmless if you have no tmux config to lose - it just writes the
default.

## Rows that act on state the host owns

A second category, found while living on the hybrid setup: rows that overwrite
nothing but drive the Omarchy side of a feature whose owner on a guest is the
host. The failure is silent state, not lost files:

| row id | what it does | what goes wrong as a guest |
|---|---|---|
| `system.lock` | `omarchy-shell lock lock` | with `omarchy.lock` disabled (no PAM), the IPC is a no-op: **the Lock row locks nothing**, and says nothing. False security - the worst row in the menu |
| `trigger.toggle.idle-lock` | writes the stay-awake indicator | the only reader of that indicator is `omarchy.idle`, disabled on a guest: the row flips state and inhibits nothing |
| `system.screensaver`, `trigger.toggle.screensaver` | ttfx + their idle plugin | both absent/disabled on a guest; dead rows |
| `update.process.hyprsunset` | kills and relaunches hyprsunset | the daemon survives, but orphaned from the host unit that supervises it |
| `setup.direct-boot` | writes an EFI entry for the **Omarchy UKI** | boot-chain takeover on a machine that boots the host's path |
| `style.hyprland` | opens `looknfeel.lua` in the editor | right where that file is wired into the user's `hyprland.lua` (the reference host's Omaland panel writes it); where it is not, the honest layer is the user's `hyprland.lua` |

Where the host has an equivalent, **replace** the row (same icon and label,
honest action). Where it does not, hide. The reference override file's
section 3 does both.

Prefer, in this order, the mechanism that needs the least adapting:

1. **An interface every host speaks.** `system.lock` is `loginctl lock-session`:
   the logind lock request, which the host's idle daemon already listens for -
   hypridle runs the `lock_cmd` from its own `hypridle.conf`, swayidle likewise.
   The row locks with whatever locker the host chose, and the override never
   names it. Prerequisite: `lock_cmd` in the `general` section of the host's
   `hypridle.conf`; without it the request goes nowhere, exactly like the
   original row. `grep lock_cmd ~/.config/hypr/hypridle.conf` says which.
2. **Their command, wrapped by a shim.** `Stay Awake` is *not* overridden. The
   row keeps calling `omarchy-toggle-idle`, and `shims/omarchy-toggle-idle`
   answers first (see below): it runs the original, so Omarchy's indicator is
   written as before, then holds a `systemd-inhibit --what=idle` for as long as
   the indicator exists. The host's idle daemon stays up - brightness, DPMS -
   and only idle is held. Stopping the host's idle unit from a menu row instead
   would leave the indicator saying one thing and the daemon doing another, and
   would tie the file to a unit name.
3. **A host unit name.** Only `update.process.hyprsunset` needs one, because
   the honest restart is of the unit that supervises the daemon. Adapt it.

`style.hyprland` decides at click time: `looknfeel.lua` if it exists **and**
the user's `hyprland.lua` loads it, the user's `hyprland.lua` otherwise. Existing
is not enough - on a guest `looknfeel.lua` is an orphan until wired (see
[`THEMING.md`](THEMING.md)), and opening a file nothing reads is the same
"I changed it and nothing changed". One override serves both kinds of host.

## Shims

`shims/` holds scripts named exactly like an Omarchy command. They win only if
the directory comes **before** `$OMARCHY_PATH/bin` on the PATH of the process
that calls the command - and `omarchy-guest-run` (hence `launch-shell`, hence
the shell and every menu row) puts it there. A terminal that types the bare
name still gets the original unless the host's environment does the same;
the reference machine does it in `~/.config/environment.d/`.

`omarchy-guest install` copies them to `~/.local/share/omarchy-guest/shims/`,
next to `bin/`, which is the layout `omarchy-guest-run` expects.

## Replacing a row instead of hiding it

Same mechanism, with an `action`. Reusing the id also **keeps the row's
position**, which a new id would not: order comes from definition order, so a
new id lands at the bottom of the submenu.

The reference machine swaps Omarchy's updater for the host's, because the host's
counts packages per source and Omarchy's does not report an inventory:

```jsonc
{
  "update.omarchy": {
    "icon": "󰏔",
    "label": "System",
    "action": "omarchy-launch-floating-terminal-with-presentation '<host updater>'"
  },
  "update.omarchy-repo": {
    "icon": "",
    "iconFont": "omarchy",
    "label": "Omarchy (repo and migrations)",
    "action": "omarchy-launch-floating-terminal-with-presentation omarchy-update"
  }
}
```

Note the second row. Omarchy's own updater is the only way to update their
checkout and run their migrations - replacing it outright leaves you unable to
update Omarchy at all. Demote it, do not delete it.
