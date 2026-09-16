# Surveying your own host

[`HOST-INVENTORY.md`](HOST-INVENTORY.md) is one machine's answers. The host there
is [HyDE](https://github.com/HyDE-Project/HyDE), and every command in it says
`hyde` somewhere. If your host is a different config manager — or your own
hand-written Hyprland config, or a bare Arch with nothing but Hyprland — that
document is an example, not an instruction.

This one is the instruction. Same questions, asked of *your* machine -
five of them from the reference machine, and a sixth the second machine added.

The output is your own `HOST-INVENTORY.md`. Write it down: the value of the
inventory is not knowing the answers once, it is being able to tell, six weeks
later, whether something you are about to remove is load-bearing.

## Method, before the questions

**Read from the running system, not from the config.** A config file tells you
what someone intended. `systemctl --user list-units`, `hyprctl binds` and
`/proc` tell you what is actually there. On the reference machine the difference
was eleven daemons running next to the Omarchy plugin that already covered them
— nothing was misconfigured, and nothing announced the overlap.

**Survey after a normal login.** Not after a reload, not in a nested session.
Session start is the only moment that fires the host's autostart, and a reload
cannot show you what a login will do.

**Beware a contaminated reading.** Something running is a fact; *why* it is
running is the part you need. On the reference machine a boot that missed two
config lines brought `waybar` and `dunst` back, and the inventory recorded them
as dependencies — true, and misleading. Before writing a row, know what started
it.

**Do it before you change anything.** The inventory is the "before" picture. It
is worth much less taken halfway through a migration, and this project's own
history is the proof: several entries in the reference inventory had to be
re-measured because the first reading was taken after ownership had already
moved.

---

## 1. Who owns the compositor entry point?

The single load-bearing fact. Everything the compositor loads is rooted in one
file, and if you remove the host without moving that first, **your next login
has no session**.

    echo "$HYPRLAND_CONFIG"
    hyprctl getoption misc:disable_hyprland_logo >/dev/null && \
      grep -rn "HYPRLAND_CONFIG" ~/.config/uwsm/ ~/.config/environment.d/ \
        /etc/environment.d/ 2>/dev/null
    systemctl --user show-environment | grep -i hyprland

Then find who *sets* it, and — this is the part that decides how hard your
migration is — **how**:

- `VAR="${VAR:-default}"` — the host yields to whoever set it first, so a file
  sorting **earlier** in the same directory wins.
- `VAR=value` — the host assigns unconditionally, so a file sorting **later**
  wins instead.

Either way it is one file and one line. What it is *not* is a reading exercise:

**Do not trust the `:-`. Measure it.** A host can declare the yielding form and
still overwrite you, because the assignment you are reading is not the only one.
HyDE is the worked example, and it cost a boot on the second machine: its env
file has the textbook `HYPRLAND_CONFIG="${HYPRLAND_CONFIG:-...}"`, but a few
lines earlier it sources `~/.local/lib/hyde/shell/activate`, and that file opens
with `HYPRLAND_CONFIG=""`. By the time the `:-` is evaluated, your value is gone.
The contract is in the text and not in the effect.

One line settles it, with your file already installed:

    (unset HYPRLAND_CONFIG HYDE_ACTIVATED
     for f in ~/.config/uwsm/env-hyprland.d/*.sh; do . "$f"; done
     echo "$HYPRLAND_CONFIG")

Clear the host's "already activated" guard too — `HYDE_ACTIVATED` here, whatever
yours is called. Without that, the host's setup script returns early and you
simulate a login that never happens.

If `HYPRLAND_CONFIG` is empty, Hyprland is reading `~/.config/hypr/hyprland.conf`
directly and you own the entry point already. That is the easy case; skip to
question 2.

> Filled example, reference machine: set by
> `~/.config/uwsm/env-hyprland.d/00-hyde.sh`, and the `:-` holds — `00-guest.sh`
> sorts earlier and wins.
>
> Filled example, second machine: same host, same line, newer version, and the
> `:-` does **not** hold. `99-guest.sh` sorts later and wins. Same host name,
> opposite answer — which is the reason this question is measured and not read.

## 2. What are the keybindings, and how many do you use?

    hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key) -> \(.dispatcher) \(.arg)"' | sort
    hyprctl binds -j | jq 'length'

Count them, then group them. The number alone is not the cost — porting all of
them to discover you use fifteen is wasted work.

The honest procedure is not a port: live on Omarchy's map for a few days and
port what you reach for and miss. Your fingers produce a better list than your
config does.

> Filled example: 173 bindings, all the host's — 80 workspaces, 34 window
> management, 17 launcher, 14 hardware, 11 utilities, 9 theming.

## 3. Which session daemons are running, and who already covers them?

Two lists, side by side. What the shell covers:

    omarchy-shell shell listPlugins | jq -r '.[] | select(.enabled) | .id'

It prints one JSON array, so pipe it: raw, it is a single unreadable line.

What is actually running that the host started:

    systemctl --user list-units --state=running --no-pager
    systemctl --user list-units --state=running --no-pager | grep -i <host-prefix>

Pair them into a table with four columns — unit, process, covered by Omarchy?,
keep or stop — and fill the third column honestly. "Partially" is a real answer
and the most useful one: it is where a shim lives, or where a plugin covers the
UI but not the policy.

**A running daemon next to the plugin that covers it is not an error and does not
log.** Two polkit agents, two clipboard histories, two battery notifiers: the one
that claimed the name first answers, the other sits there. You only find these by
putting the two lists next to each other.

### The third place daemons come from

If your session runs under **uwsm**, the host's autostart and Omarchy's autostart
are not the whole list. uwsm also runs XDG autostart, and what starts there
answers to neither:

    systemd-analyze --user blame | grep autostart
    ls /etc/xdg/autostart/

The override is a file of the same name in `~/.config/autostart/` carrying
`Hidden=true`. The packaged file stays as it is.

**The rule that generalises:** a daemon that survives removal from every config
you know about is starting from a place you have not looked at yet. Keep looking
before you conclude the removal failed.

## 4. What does the host give you that Omarchy has no equivalent for?

This is the question with no command, and the one that decides whether "guest"
is a phase or a permanent arrangement. Go through what you actually use — the
updater, a workflow, a script your bar calls — and ask, for each:

- does Omarchy ship something equivalent?
- if not, how coupled is it? A self-contained script you can copy out is a
  different problem from something wired into the host's config chain.

A dependency that is 900 lines of standard-library Python is not really a
dependency; it is a copy away from being yours. One that reaches into the host's
theme pipeline is.

> Filled example: the package updater — `system.update.py` + `pm.py`, 267 + 630
> lines importing nothing but the standard library, called by our own bar widget
> and menu row. Load-bearing by our own doing, and the easiest to decouple.

## 5. Which files in `~/.config` do both sides write?

The four questions above all look at **processes**. This one does not, and that
is why it is easy to miss: there is no second daemon, no duplicated unit, no
name to lose a race for. An Omarchy plugin reads a config file in `~/.config`,
your host wrote that same file, and the plugin does exactly what it is told by a
configuration that was never meant for it.

    # every user config Omarchy ships, next to yours
    for f in $(cd "$OMARCHY_PATH/config" && find . -type f | sed 's|^\./||'); do
      [ -f "$HOME/.config/$f" ] || continue
      cmp -s "$HOME/.config/$f" "$OMARCHY_PATH/config/$f" \
        && echo "igual     $f" \
        || echo "DIFERENTE $f"
    done

`DIFERENTE` is not a verdict - most of them are your own customisation, which is
the point of a user config. The question to ask of each one is narrower: **does
a plugin you have enabled read this file?** If yes, and the file came from the
host, the feature is on and inert.

> Filled example, second machine: `hypr/hyprsunset.conf`. `omarchy.nightlight`
> was enabled and spawns `hyprsunset`, which reads that path - and the file was
> HyDE's, carrying two empty `profile { }` blocks. Night light switched on,
> doing nothing, for as long as nobody looked. `omarchy-refresh-hyprsunset`
> replaces it with Omarchy's. `omarchy-guest doctor` checks this one now.

The failure mode is worth naming because it generalises past this project:
**two owners of a file is quieter than two owners of a process.** A process at
least shows up twice in `ps`.

## 6. Who owns the theme?

    ls ~/.local/state/omarchy/current/theme        # what the shell reads
    # and whatever your host's equivalent is

Expect two pipelines with no link between them. They will drift, and the drift
is silent — on the reference machine they sat on different themes for days.

This never breaks a session, so it is easy to postpone. It is also why a guest
install feels unfinished: the desktop stops looking like one desktop.

Pick **one** owner and drive the other from a hook. Which one depends on which
reaches more surfaces on your machine — GTK, cursor, terminal, editor,
launcher, lock screen. [`THEMING.md`](THEMING.md) is this step done, surface by
surface, and the traps in it are mostly not HyDE-specific.

**The wallpaper deserves its own line.** A hook that repaints on every theme
change still loses the next login if the host's daemon remembers its own
wallpaper and reapplies it at session start. Test this by logging out, not by
changing themes.

---

## Then what

With the answers written down, the removal order in
[`HOST-INVENTORY.md`](HOST-INVENTORY.md#order-that-makes-removal-possible)
applies as written — it is ordered by dependency, not by host. Each step is
independently reversible, and the last one is worth repeating here: the host
being on disk costs nothing. "Can remove" and "should remove" are different
questions, and only the first one is technical.

If your survey turns up a category these questions miss, that is worth a pull
request to this file - question 5 got here that way. The shape of the list is the part that is meant to
transfer.
