---
name: open-in-vscode
description: Open a file, folder, or workspace in the user's LOCAL VSCode from a remote SSH session (or locally). Use whenever the user asks to "open this in VSCode / code", "покажи в VSCode", "открой файл/папку/workspace в редакторе". Runs the `code-remote` helper — do NOT call `code` or `kitty @` directly.
---

# Open in VSCode (`code-remote`)

When the user wants to open something in their VSCode, use the `code-remote`
helper script (on PATH via `~/.dotfiles.scripts`). Do **not** invoke `code` or
`kitty @` yourself — `code-remote` handles the remote-vs-local logic and the
kitty remote-control bridge.

## How to call it

```
code-remote <path> [line]
```

- File:              `code-remote src/app.ts`
- File at a line:    `code-remote src/app.ts 42`   (or `code-remote src/app.ts:42`)
- Folder / project:  `code-remote .`  or  `code-remote path/to/dir`
- Workspace:         `code-remote path/to/proj.code-workspace`

Paths may be relative — the script resolves them to absolute.

## What it does

- **In a remote SSH session** (connected via `kitten ssh`): tells the user's
  **local** kitty to launch `code --remote ssh-remote+<host> <path>`, so their
  local VSCode opens the file over Remote-SSH, connected to this same host.
- **Locally**: just runs `code` directly.

## Notes

- Requires the session to be opened with `kitten ssh` (kitty remote control must
  be forwarded). If it isn't, the script prints a clear error — relay it; don't
  try to work around it with raw `code`/`kitty @`.
- The Remote-SSH host defaults to `$(hostname)`. If VSCode fails to connect
  because the SSH-config alias differs, retry with
  `CODE_REMOTE_HOST=<ssh-alias> code-remote <path>` (ask the user for the alias).
