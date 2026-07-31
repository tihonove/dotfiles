# dotfiles

Личные конфиги. Собираются заново — старая версия лежит в `~/dotfiles-old`
и переезжает сюда по кусочкам, осознанно.

## Структура

```
.
├── install.sh       # раскладывает симлинки
├── update-tools.sh  # ставит внешние бинарники в ~/.local/bin
├── README.md
├── home/            # зеркало ~ : home/<path> -> ~/<path>
└── system/          # то, что ставится в /etc руками, под sudo
```

В корне репы — только служебное. Всё, что реально попадает в домашний
каталог, живёт в `home/`.

## Установка

```sh
git clone https://github.com/tihonove/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

Линкуются файлы, а не каталоги: `install.sh` обходит `home/` в глубину,
создаёт недостающие каталоги в `~` обычными и делает симлинк на каждый файл.
Существующие файлы сохраняются рядом с суффиксом `.backup.YYYYMMDD_HHMMSS`.

## Внешние тулзы

```sh
~/.dotfiles/update-tools.sh
```

Качает бинарники в `~/.local/bin`. В git их не кладём: в старых dotfiles
вендоренный `.starship.arm` был собран под 32-битный ARM и на aarch64 не падал,
а вешал старт шелла намертво. Машина ARM, сборки берём musl.

## Что внутри

- `.bashrc` — минимальный, растёт по шагам
- **starship** — промпт, конфиг `home/.config/starship.toml`
- **JetBrainsMono Nerd Font** — ставится в `~/.local/share/fonts`,
  через `home/.config/fontconfig/fonts.conf` становится дефолтным `monospace`
- **sway** — база (раскладки, тачпад, тема, автозапуск панели), биндов почти нет
- **waybar** — панель, порт стокового конфига без мёртвых модулей

## devsy

```sh
~/.dotfiles/update-tools.sh   # ставит CLI
~/.dotfiles/devsy-setup       # настраивает ssh-провайдер (идемпотентно)
```

Заход в контейнеры — через `~/.ssh/config` (лежит в репе), пользователем
`vscode`, а не root:

```sh
ssh vexx.devsy        # то же самое: devsy ws ssh vexx --user vscode
ssh anki-cli.devsy
ssh devsy-host        # сама облачная машина
```

⚠ В `home/.ssh/config` записан адрес облачной машины. Если репа станет
публичной — учитывать.

Воркспейсы живут контейнерами на облачной машине, а их метаданные — локально в
`~/.devsy/contexts/default/workspaces/`. На новой машине этих метаданных нет, и
`devsy ws up` поднимет **новый** контейнер вместо подключения к старому. Как
восстановить метаданные из копии, которую держит агент на хосте, — расписано в
конце `devsy-setup`.

## Сознательно не переносим

Решённое, чтобы не возвращаться при следующем заходе в `~/dotfiles-old`:

- **kitty remote control** — `allow_remote_control` + `listen_on unix:/tmp/kitty`
  и `ssh.conf` с `forward_remote_control yes`. Первое было нужно yazi, второе —
  открытию локального VSCode из ssh-сессии и отдаёт удалённому хосту управление
  локальным kitty. Не берём ни в каком виде.
- **вендоренные бинарники в git** — `.starship.arm` / `.starship.x86`. Неверная
  арка не диагностируется до запуска: на aarch64 32-битный бинарник не падает,
  а вешает старт шелла. Всё внешнее — через `update-tools.sh`.
- **kitty.cage.conf** — обвязка для cage (киоск), самого cage в системе нет.

Отложено, не забыть:

- **Super → tmux** (22 маппинга в kitty + `user-keys` в `.tmux.conf`) — вернуться
  при переносе tmux. Super+1..9 сейчас заняты столами sway, схему придётся либо
  переводить на другой модификатор, либо освобождать Super.

## Пакеты

Ставятся руками, в репу не входят:

```sh
sudo apt install --no-install-recommends brightnessctl
sudo install -m 644 system/90-backlight.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger -s backlight -c add
sudo usermod -aG video "$USER"   # применяется после релогина
```
