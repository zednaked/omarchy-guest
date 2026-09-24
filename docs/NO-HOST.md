# No host at all: the zednet install

The first machine born without a host. It's the end state of "Order that makes
removal possible" in [`HOST-INVENTORY.md`](HOST-INVENTORY.md), tested on a real
disk and not reasoned about: minimal Arch, then Hyprland, quickshell, an Omarchy
checkout, and this repo. **The official installer never ran on this machine.**
It takes the disk and the bootloader, and this machine has a data drive that
must not be touched.

Written live on 24/09/2026. The raw log, with commands and output, is in
`~/zednet/ACHADOS.md` on the main machine.

Machine: Avell High Performance 1555 (Clevo), i7-8750H, UHD 630 + GTX 1060
Mobile, 24 GB RAM. Arch on a 256 GB SATA SSD, systemd-boot, systemd-networkd.
sddm (added later, see the end; the first login was tty1 autostart).

---

## The numbers

| stage | `pacman -Q` | `-Qe` | note |
|---|---|---|---|
| `pacstrap` base | 150 | 9 | `base linux linux-firmware-{intel,realtek} intel-ucode e2fsprogs openssh rsync sudo` |
| + desktop | 299 | 19 | `hyprland quickshell uwsm gum xdg-terminal-exec qrencode wtype git foot ttf-jetbrains-mono-nerd` (+149) |
| + kitty | 304 | 20 | installed unasked right after first login, probably by Omarchy, see below (+5) |
| + `jq` | 306 | | required, and missing from the doctor (+2) |
| + `dolphin` | 480 | | asked for by the user; **+174**, the whole KDE Frameworks stack |
| + `plymouth` | 482 | 23 | boot splash (+2) |

For comparison, the upstream installer's `install/omarchy-base.packages`
names 151 packages *before* dependencies.

Boot (`systemd-analyze`, before plymouth): 17.3 s, which is firmware 7.7,
loader 3.9 (menu `timeout 3`), kernel 1.5, initrd 2.0 and userspace 2.1.

RAM: 1247 MB used 2m46s after login, **not idle** (a kitty and a `journalctl`
were open). A clean idle reading is still owed. The resident top was quickshell
234 MB, kitty 144 MB and Hyprland 139 MB.

---

## What the entry point looks like with no host

Most of this repo is about *inverting* ownership (`HYPRLAND_CONFIG`,
`00-guest.sh` vs `99-guest.sh`, the `hyde` guard in `hypr/hyprland.lua`). With
no host, none of that applies. There's nothing to invert:

- `~/.config/hypr/` is a plain copy of the checkout's `config/hypr/`. Hyprland
  finds `hyprland.lua` there by default, so no variable is set.
- Only `config/{hypr,omarchy,foot}` was copied, not the whole `config/` tree,
  which also has chromium, obsidian, opencode and a dozen more.

### The environment is the actual work

On a packaged install `OMARCHY_PATH` and `PATH` come from `/etc/profile.d`,
`/etc/skel` and `/usr/share/uwsm/env.d/10-omarchy`, which all source
`default/bash/env-bootstrap` **at `/usr/share/omarchy`**. A checkout has none
of these, and `10-omarchy` silently skips the bootstrap it can't find. Three
files replace them:

| file | who reads it |
|---|---|
| `~/.config/uwsm/env` | the compositor, via uwsm: exports `OMARCHY_PATH`, prepends `bin/`, sources `default/uwsm/env.d/10-omarchy` |
| `~/.config/environment.d/60-omarchy.conf` | systemd user units |
| `~/.bash_profile` | login shells and SSH. On tty1 it runs `exec uwsm start -g -1 -e -D Hyprland hyprland.desktop`, the `Exec` of their own `omarchy.desktop` |

Trap: a tty1 login that started *before* `~/.bash_profile` existed stays a plain
shell. Log out and in again.

---

## What broke, and what the doctor doesn't see

1. **`bootstrap` contradicts the README.** It installs all of
   `omarchy-base.packages` (151) plus `system/packages/flavor.packages`. The
   README says "five packages". Proposal: `bootstrap --minimal` with
   `hyprland quickshell git` plus the doctor's runtime deps, and keep the full
   list as the opt-in.
2. **`jq` is a runtime dep and isn't in the doctor's list.** 76 of 459 commands
   in `bin/` call it, including `omarchy-notification-send`. First symptom: the
   first-run step "show welcome notification" exits 127.
3. **Packaged units point to `/usr/bin`.** `default/systemd/user/*.service` use
   `ExecStart=/usr/bin/omarchy-*`, and in a checkout those live in
   `$OMARCHY_PATH/bin`. Three were copied to `~/.config/systemd/user/` with
   `sed` (`recover-internal-monitor`, `sleep-lock`, `crash-watch`). `bt-agent`
   and `fcitx5` were left out (binary absent), and so was `migrate-notify`
   (doesn't apply).
4. **First-run is all-or-nothing per step, so it retries forever.**
   `enable-user-units.sh` enables seven units, plus `owed.service`, in one
   `systemctl enable --now`. One missing unit fails the step, and the step
   failing keeps first-run from being marked done. The doctor warns that
   first-run will repeat but counts the units that were **refused on purpose**.
   Proposal: a list of refused units the doctor accepts.
5. **`gsettings` without schemas.** `gnome-theme.sh` and
   `gtk-primary-paste.sh` fail because `org.gnome.desktop.interface` comes from
   `gsettings-desktop-schemas`, which isn't installed. That's harmless until the
   first GTK app.
6. **kitty arrived by itself.** `pacman -S --noconfirm --needed kitty` at 15:16,
   right after the first login. foot was installed, but `xdg-terminals.list`
   wasn't copied, so Omarchy installed its own choice. It's +5 packages that
   nobody picked. (To confirm: which command triggered it.)
7. **`omarchy-guest system` writes the sddm config even with no display
   manager.** With no DM enabled, `dm_ativo` is empty and the section falls
   through to writing `/etc/sddm.conf.d/50-omarchy-guest.conf`. Here `system`
   wasn't used for that reason. Plymouth was done by hand.
8. **Plymouth needs two steps that `system` doesn't do.** The `plymouth` hook in
   `mkinitcpio.conf` (after `systemd`) and `splash` on the kernel command line.
   `system` assumes the reference machine, where both already existed.
9. **`omarchy-guest-theme-boot` calls `sudo -n`.** With no cached credential it
   can't escalate. Here it ran as root with `HOME=/home/zed`. Without PIL
   (`python-pillow`) the progress bars keep their old colour.
10. **Boot order only held when set in the firmware setup.** Machine-specific,
    but it cost three reboots. `efibootmgr -o` and `bootctl install` were both
    undone by the firmware on the next boot, which fell into a stale `Ubuntu`
    GRUB on another drive's ESP. The fix was Boot Option #1 in the BIOS setup.

## What worked the first time

- `OMARCHY_THEME_HEADLESS=1 omarchy-theme-set tokyo-night` with no session.
- `omarchy-guest install`, with no host: menu extension, updater, shims,
  hooks, board.
- `sudo omarchy-apply-lock`.
- First login: one quickshell, `hyprctl configerrors` empty.
- doctor: **3 blockers and 6 warnings before**, **0 blockers and 3 warnings
  after**.

## Later the same day: login screen and splash

- **sddm instead of tty1 autostart.** The user expected a login screen.
  `sddm` plus the astronaut theme's Qt6 deps added **+9** (491 total), few
  because dolphin had already brought Qt6. `sddm-astronaut-theme` is AUR-only
  and this machine has no AUR helper, so the theme directory was copied from
  the reference machine, **outside pacman**. The `omarchy.desktop` session came
  from the checkout's `default/wayland-sessions/` into
  `/usr/share/wayland-sessions/`. `/var/lib/sddm/state.conf` was pre-seeded so
  the first login picks it.
- `omarchy-guest-theme-boot --no-initramfs` painted the sddm theme (19 colours)
  with no issue.
- systemd-boot `timeout 0`.

## Updating Omarchy: every path that breaks this install, and how each is closed

The user's rule: *the Omarchy updater breaks the whole install, so it must not
run unsupervised, and it has to hold across reboots and updates.* On a fresh
checkout there were **five** ways in, and the doctor saw only one of them.

| # | path | what it would do here | closed by | survives |
|---|---|---|---|---|
| 1 | bar widget `omarchy.system-update` (in the default `shell.json` layout) | click → `omarchy-update` | replaced by `zed.updates` in `~/.config/omarchy/shell.json` (backup `.pre-zed-updates`) | reboot yes; `omarchy-refresh-shell` would undo it → guarded (5) |
| 2 | first-run `wifi.sh` → `notify_update` ("Click to update the system") | notification whose click runs `omarchy-update`; and first-run **retries every login** while any step fails | `omarchy-done mark first-run-user` | yes, it's a state marker |
| 3 | menu row `update.omarchy-repo` (kept by this repo's extension as the "demoted" way to update Omarchy) | raw `omarchy-update`: `git pull` + migrations + config refresh | `"when": "false"` added on this machine (backup `.pre-zednet`) | yes, `extensions/` survives `omarchy update` (MENU-OVERRIDES.md) |
| 4 | **124 pending migrations**, because a fresh clone has no markers | `omarchy-migrate` would run the whole history: 28 by policy, 21 to decide, among them *"Install the Omarchy kernel and make it the first Limine boot entry"* on a systemd-boot machine | every marker touched in `~/.local/state/omarchy/migrations/`, which is **what their own finalizer does on a fresh install** (see `install/user/first-run/audio-tuning.sh`) | yes. New migrations after a pull show up as pending again, which is correct |
| 5 | anyone or anything calling the commands by name | same as above, plus `refresh-limine`/`refresh-pacman`/`refresh-sddm`/`refresh-plymouth` overwriting boot, repos, login and splash | **PATH guard** `~/.local/share/omarchy-guest/guard/bin/`, **in front of** `$OMARCHY_PATH/bin` in all three env files | yes. It lives outside the checkout, so a `git pull` doesn't touch it |

Guarded names (symlinks to one script, `omarchy-guard`): `omarchy-update`,
`omarchy-update-dev`, `omarchy-migrate`, `omarchy-migrate-notify`,
`omarchy-upgrade-to-quattro`, `omarchy-channel-set`, `omarchy-refresh-{config,
hyprland,shell,plymouth,sddm,limine,pacman}` and `omarchy-reinstall{,-configs,-pkgs}`.
Each prints why and sends a notification. `omarchy-migrate --pending` answers
"nothing" so `migrate-notify` stays quiet. `OMARCHY_GUEST_ALLOW=1 <cmd>` runs
the real one.

Limits: `sudo` uses `secure_path`, so a root call bypasses the guard. Nothing
in the session calls these as root, but it isn't airtight.

What the doctor should learn from this (proposals):
- check the **bar layout** for `omarchy.system-update`, not only the menu;
- on a checkout, count **migrations without markers** and treat a large number
  as a blocker ("fresh clone, run the finalizer equivalent");
- check that first-run is marked or will pass, because a first-run that
  retries forever keeps re-arming the update notification;
- the guard itself belongs in this repo (it's `shims/` with a different job:
  refuse instead of wrap), installed by `install`.

### Updating Omarchy, the safe way (by hand)

    cd ~/.local/share/omarchy && git fetch origin quattro
    omarchy-guest-contract --ref origin/quattro --commits   # what breaks
    omarchy-guest-migrations --ref origin/quattro           # what would run, classified
    git merge --ff-only origin/quattro
    omarchy-guest-migrations --apply-policy                 # mark what the policy skips
    OMARCHY_GUEST_ALLOW=1 omarchy-migrate                   # in a real terminal (sudo)
    omarchy-guest doctor

Never `omarchy-update`: it also runs the `refresh-*` family and the pacman
side, and on this machine both are ours.

### System packages

`pacman -Syu` is safe here. There's no Omarchy repo in `pacman.conf`.
`mkinitcpio.conf` and `loader.conf` were edited, and pacman keeps local edits
(`.pacnew`). The sddm theme was copied outside pacman, so no update touches it.

## Never sleep, never screensaver: a default, not a tweak

After the first idle period the screensaver started and failed:
`omarchy-screensaver` calls **`ttfx`**, which is in `omarchy-base.packages`
(line 112) but only exists in Omarchy's repo and the AUR, not in Arch's.

The user's rule: the machine doesn't enter the screensaver and doesn't sleep,
and **that must be the default**. On the reference machine this isn't a plugin
but a *disabled* one: `"disabledPlugins": ["omarchy.idle"]` in `shell.json`.
`omarchy.idle` drives screensaver (150 s), lock (300 s) and suspend. There
the host's hypridle kept the idle policy. Here there's no hypridle, so
disabling it means no idle action at all, which is what was asked.

Done on zednet:
- `omarchy plugin disable omarchy.idle` (live, with the session env). It
  writes `disabledPlugins`, and the backup is `shell.json.pre-idle`.
- `/etc/systemd/logind.conf.d/10-zednet-nao-dorme.conf`: `HandleLidSwitch*`
  and `IdleAction` set to `ignore`, because a backup box must not suspend when
  the lid closes. Applied with `systemctl kill -s HUP systemd-logind`.
- `ttfx` **not** installed. With idle off nothing launches the screensaver,
  but the menu row still does, and it will fail the same way.

For the future no-host repo: ship `omarchy.idle` disabled and the logind
drop-in by default, with enabling idle as the opt-in. The doctor should warn
when `omarchy.idle` is on and `ttfx` is missing, because that screensaver can
only fail.

## After the reboot (24/09, 15:32)

- **Boot 11.1 s** (was 17.3): firmware 4.0, loader 1.0 (`timeout 0`),
  kernel 1.4, initrd 2.1 (now with plymouth) and userspace 2.5.
- **RAM idle: 1198 MB used**, 2m41s after login, untouched (491 packages).
  The top was quickshell 248 MB, Hyprland 137 MB, **Xorg 82 MB**, Xwayland 47
  MB, uwsm 25 MB and sddm+helper 44 MB. The Xorg is the sddm greeter's X server
  and it stays alive after login. Candidate saving: sddm with
  `DisplayServer=wayland`, so Xorg isn't needed for login at all.
- Everything survived the reboot: guard first on the session's `PATH`,
  `omarchy.idle` disabled, `zed.updates` on the bar, one quickshell.

## Sound and network: what the panels actually call

The user noticed neither sound nor Wi-Fi showed up. Both were left out of the
minimal list on purpose, and the doctor asked for neither. What the shell calls:

| panel | backend | package |
|---|---|---|
| network (`panels/network/Model.js`) | **`nmcli`** (35 calls), not iwd | `networkmanager` |
| audio | `pactl` (29), `wpctl` (7) | `pipewire pipewire-pulse wireplumber` |

- Audio: **+22**. User sockets `pipewire`, `pipewire-pulse` and `wireplumber`
  enabled. `pactl info` → PulseAudio on PipeWire 1.6.9, sink "Áudio interno".
- NetworkManager: **+12**. **Wi-Fi only.**
  `/etc/NetworkManager/conf.d/10-so-wifi.conf` marks `en*`/`eth*` unmanaged,
  so the cable stays with systemd-networkd and the SSH session never dropped.
  `nmcli device`: `wlo1 wifi unavailable` (the radio is hard-blocked by the EC,
  Fn+F4) and `enp3s0 unmanaged`.
- Total **525** packages.

For the no-host repo: the "five packages" list isn't enough for a usable
desktop. A realistic minimum adds `jq`, the PipeWire trio and `networkmanager`.
The doctor's runtime-deps list should add at least `jq`, `nmcli`, `pactl` and
`wpctl`.
