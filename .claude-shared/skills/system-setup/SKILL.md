---
name: system-setup
description: Consult and update the local-machine setup log at ~/.system-setup/ when configuring, diagnosing, or fixing anything on THIS machine — audio, Bluetooth, drivers, systemd/user services, network, kernel/udev, system configs, or dotfiles. Use it to check for prior manual setup before changing something, and to record what was changed after.
---

# Local machine setup log

`~/.system-setup/` is a running journal of every manual configuration/fix made to
this machine. Use it whenever a task involves setting up, diagnosing, or fixing the
local system (not application code).

## Before changing something

Read `~/.system-setup/README.md` (the index) and any relevant entry first. A prior
fix may explain the current behavior, record a gotcha, or show how a subsystem is
already configured. Don't re-derive what's already documented.

## After changing something

First decide whether it's worth documenting at all. **Skip the log for straightforward,
low-value actions** — a standard package install from an official repo, a one-line config
tweak, anything with no root-cause investigation, no gotchas, and an obvious/standard revert.
If the "Cause" and "Side effects / gotchas" fields below would be empty, don't write an entry.

Document only changes where future-you would lose something without a note: a non-obvious
root cause, a workaround, a fix that touches several files, tricky reverts, or upgrade
caveats. When in doubt, prefer not writing — the log is for hard-won context, not a command
history.

For the changes worth keeping, document each in `~/.system-setup/` as its own markdown file
(one topic per file). Capture:

- **Symptom** — what was broken / why the change was made.
- **Cause** — the actual root cause, once known (note superseded theories).
- **What was done** — exact files edited and the change, commands run.
- **Verification** — how it was confirmed to work.
- **Revert** — how to undo it.
- **Side effects / gotchas** — anything non-obvious, and notes for future upgrades.

Then add a one-line pointer to the new file in `~/.system-setup/README.md`.

## Goal

Keep `~/.system-setup/` the single source of truth for the machine's manual state,
so context about how it's configured is never lost between sessions.
