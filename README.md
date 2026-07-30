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

## Пакеты

Ставятся руками, в репу не входят:

```sh
sudo apt install --no-install-recommends brightnessctl
sudo install -m 644 system/90-backlight.rules /etc/udev/rules.d/
sudo udevadm control --reload && sudo udevadm trigger -s backlight -c add
sudo usermod -aG video "$USER"   # применяется после релогина
```
