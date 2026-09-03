# hyde-updater (vendored)

This directory is **not** MIT like the rest of this repository. It is
**GPL-3.0**, and it stays that way.

## Where it comes from

`system.update.py`, `pm.py` and `package_managers/` are taken from
[HyDE](https://github.com/HyDE-Project/HyDE), which is licensed under
GPL-3.0. `LICENSE` here is HyDE's own copy, unchanged.

## Why it is here

Omarchy's updater reports no inventory: it updates and tells you nothing about
what was pending or where it came from. HyDE's does - it has a backend per
package manager, counts per source, and writes the result as JSON that a status
bar can read.

The bar widget in `plugins/zed.hyde-updates` and the menu override in
`extensions/` both call it. Before vendoring, that meant the widget only worked
on a machine that also had HyDE installed, which defeats the point of a guest
install. Vendoring removes that dependency.

## What was changed

Kept deliberately small and marked in place - every edit carries an
`omarchy-guest:` comment.

1. **State directory.** `$XDG_RUNTIME_DIR/hyde` -> `$XDG_RUNTIME_DIR/omarchy-guest`.
   The old path is still *read* as a fallback, so a machine migrating from the
   host does not show zero until the first fresh query finishes. Zero is
   precisely the misleading answer here.
2. **`refresh_waybar` is a no-op.** The original signalled waybar with
   `SIGRTMIN+20`. A guest install has no waybar; the Omarchy shell reads the
   JSON instead of listening for a signal. Kept as a function so call sites did
   not need touching.
3. **`show_fastfetch` calls `fastfetch` directly**, instead of going through
   `hyde-shell`, which does not exist without HyDE.

Nothing else was modified. Upstream fixes can be pulled back in by re-copying
the files and re-applying these three edits.

## Licensing note

Calling this from the widget is a subprocess invocation, not linking, so the
QML in `plugins/` is unaffected by the GPL. Redistributing these files, which
is what this directory does, requires keeping the license and the notice - hence
this file.
