---
name: tsunami-ui
description: Запустить (или перезапустить) дев-сервер фронта Tsunami (ui/gold/applications/tsunami) из текущего или любого worktree nebo в отдельной tmux-панели — https://local.tsunami.nebius.dev. Использовать по «запусти фронт», «подними цунами UI», «перезапусти фронт», «покажи что получилось на локальном фронте», а также в конце задачи по фронту цунами, когда пользователь хочет посмотреть результат.
---

# Запуск фронта Tsunami

Скрипт: `~/.claude/skills/tsunami-ui/tsunami-ui.sh` (он же `~/bin/tsunami-ui`).

```sh
~/.claude/skills/tsunami-ui/tsunami-ui.sh [--gen] [--window] [DIR]
```

- `DIR` — любой путь внутри чекаута/worktree nebo; по умолчанию cwd. Запускай из
  **того worktree, где делалась задача**, а не из основного чекаута.
- `--gen` — принудительно `fdk generate` (нужно после смены зависимостей/proto или
  если старт падает на отсутствующих артефактах). Без флага generate идёт только
  когда в worktree ещё нет `fdk_start.sh`.
- `--window` — фоновое tmux-окно вместо сплита текущей панели.

На машине всегда один фронт: скрипт сам гасит предыдущий (из любого worktree) —
спрашивать не нужно. Работает только внутри tmux.

## После запуска

Скрипт печатает id панели (`%NN`). Дождись готовности, читая панель:

```sh
tmux capture-pane -p -t %NN | grep -v '^$' | tail -8
```

Готово, когда `client ... compiled` и `[type-check] no errors found`; порт 443
слушается (`ss -ltn | grep ':443 '`). Сообщи пользователю URL
https://local.tsunami.nebius.dev и id панели.

## Грабли

- **npc-логин.** Перед generate скрипт делает `npc iam whoami --profile testing`:
  если сессия протухла, в панели появится ссылка на логин — её жмёт пользователь,
  сам ты это сделать не можешь. Увидел ссылку в панели → попроси пользователя
  нажать и жди. Внутри `fdk generate` ссылка не видна (TUI глотает stderr) —
  поэтому логин вынесен до него.
- **`could not open a new TTY`** — `fdk generate` нельзя гонять из Bash-тула
  напрямую, только в панели (скрипт так и делает).
- **Пустой `.secret.json`** в `ui/gold/applications/tsunami` после прерванного
  generate — удали его и запусти с `--gen`.
- **Порт 443.** У каждого worktree свой bazel output base и свой node; скрипт
  сам ставит ему `cap_net_bind_service` через `sudo setcap` (sudo без пароля).
- Проверка, что фронт ответил: `curl -sk -o /dev/null -w '%{http_code}' https://local.tsunami.nebius.dev/`
  → 302 на auth.
