# The contract with upstream

The guest is glue. It calls their commands by bare name, overrides rows in
their menu by id, drops plugins into the directory their shell scans, and reads
state files they write. None of that is an API anyone promised. It is a
contract we inferred by reading their code, and every one of their updates can
retire a piece of it without anybody meaning to.

`omarchy-guest-contract` turns that inferred contract into assertions that run
**against a ref, before the update lands**, and never touch the running
checkout.

    omarchy-guest-contract                       # against the installed tree
    omarchy-guest-contract --ref origin/quattro  # against what is coming
    omarchy-guest-contract --ref origin/quattro --commits
    omarchy-guest-contract --ref origin/quattro --json

It resolves the ref with `git archive` into a temporary directory. No checkout,
no worktree, no fetch: the shell it is checking is the one currently drawing
the screen, and inspecting the future cannot disturb the present.

## The verdict is differential

A check that fails is not automatically a regression. It can also be a note of
ours that rotted months ago and nobody noticed. The command tells the two
apart by running the same assertion against a baseline - the ref recorded in
`contract/verified` - and reporting:

| verdict | meaning | what to do |
|---|---|---|
| `+` ok | holds on the target | nothing |
| `x` broke | held on the baseline, fails on the target | this is the update breaking us |
| `!` stale | fails on both | our note is out of date, fix the note |

Exit code: `0` clean, `1` only stale, `2` something broke.

## What it checks

Most of it is extracted from this repo on every run, because a hand-written
list of dependencies rots faster than the code it describes:

- **commands** - every `omarchy-*` name that appears in our scripts, menu
  entries, shims and hooks has to exist in their `bin/`.
- **menu ids** - every id `extensions/omarchy-menu.jsonc` overrides has to
  exist in their `default/omarchy/omarchy-menu.jsonc`. An id that exists in
  neither is a row we create, or a row they retired - the report says which.
- **QML symbols** - each `bar.*`, `Color.*` and `Style.*` our plugins read is
  checked *in the file that has to define it for us*, not anywhere in
  `shell/`. Since [Restrict third-party shell plugin capabilities][cap]
  (01/09/2026) a third-party widget no longer receives their `Bar`; it receives
  the `shell/Ui/PluginBarApi.qml` facade. A property that survived on the Bar
  and was left out of the facade reads as fine under a broad grep and arrives
  `null` at runtime. That is exactly the failure this check exists for.

The rest is declared in [`contract/surface.tsv`](../contract/surface.tsv), one
line per dependency:

| kind | assertion |
|---|---|
| `file` | the path exists in their tree |
| `grep` | `PATTERN::PATHSPEC` matches - the mechanism is still there |
| `absent` | `PATTERN::PATHSPEC` must NOT match - our premise dies if it does |
| `echo` | `PATTERN::THEIRS::OURS` - everything matching in their file appears in ours too, for the lists we copy |
| `watch` | pathspec used by `--commits` to filter their log |
| `ignore` | a token the automatic extraction picks up that is not really a command |

`echo` is the one that catches the quiet class of break: not the mechanism
disappearing, but a list growing on their side while our copy stays behind.
The background extensions are the live example - their theme can point
`current/background` at a video since [#6792][video], and the host's daemon
only paints images.

## What it does not check

It reads files. It does not run the shell, does not render a widget, and
cannot see a QML property that exists but changed meaning, a command that kept
its name and changed its arguments, or anything whose only symptom is at
runtime. It narrows what you have to look at by hand; it does not replace
looking. `omarchy-guest doctor` is the other half - it reads the running
machine.

## The workflow

`omarchy-guest update` is the workflow; each step is a gate that stops the
rest instead of an item on a list.

    omarchy-guest update              # fetch + gates, read-only
    omarchy-guest update --apply      # gates, ff-only pull, migrations, install, shell restart, doctor
    omarchy-guest update --pin        # after looking at the live session: move contract/verified
    omarchy-guest update --rollback   # back to the ref from before the last --apply

The gates, in order:

1. **Checkout** - clean tree, fast-forward possible. On a machine installed by
   omarchy-zero the checkout is detached at the pin; the target is then
   `origin/quattro` by name.
2. **Contract** - `omarchy-guest-contract --ref <upstream> --commits`. A break
   closes the gate. **Fix it**, and add the assertion that would have caught
   it to `contract/surface.tsv`: a break found by hand and not encoded is a
   break found by hand again.
3. **Migrations** - every pending one has to have an action. One classified
   `root` needs an `id:` line in `contract/migration-policy.tsv`, with the
   reason checked on the machine, not read from the title.
4. **Rewritten skips** - a migration we skipped and they later rewrote is
   flagged: the marker keeps it skipped forever, and the reason may no longer
   hold (1788163635, 29/09/2026: skipped for calling `/usr/bin/...`, rewritten
   to call `$OMARCHY_PATH/bin/...`). Not a gate - a re-read.
5. **TTY** - `--apply` refuses migrations that call `sudo` without a terminal;
   there the sudo fails silently and the marker is written anyway.

The pin moves only with `--pin`, only when the doctor on the live session has
no blocker - it means "this ran here", not "this looked fine in a diff".
Every `--apply` is logged in `~/.local/state/omarchy-guest/updates.tsv`, which
is where `--rollback` reads the previous ref from. Migrations do not roll back.

**Each update should leave the pipeline better than it found it.** Whatever
was decided by hand this time - a policy line, a surface assertion, a
classifier false positive - goes into the repo, so next time it is automatic.

## More than one machine

The pin is per repo, but a verified ref is per machine: the same upstream
commit can be clean on the host that has `wallpaper.sh` and broken on the one
that does not. `--json` exists for that - it prints the full check list plus
the hostname and date, so two machines can be compared instead of re-argued:

    omarchy-guest-contract --ref origin/quattro --json > /tmp/contract.$(hostname).json

Run it on both, diff the two files, and what is left is the machine-specific
part - which is where every expensive surprise in this project has come from.

[cap]: https://github.com/basecamp/omarchy/commit/1702cf0b
[video]: https://github.com/basecamp/omarchy/pull/6792
