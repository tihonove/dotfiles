#!/bin/bash

# Установка/обновление внешних CLI-тулзов в ~/.local/bin.
#
# Бинарники в git не кладём. Прошлая версия dotfiles вендорила их в репу, и
# битый `.starship.arm` (32-битный ARM) на aarch64 не падал с ENOEXEC, а
# намертво вешал старт шелла внутри `$(starship init bash)`.
#
# Машина одна, ARM. Качаем musl-сборки — не зависят от версии glibc.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"

if [[ "$(uname -m)" != "aarch64" ]]; then
    echo "❌ Скрипт рассчитан только на aarch64, тут $(uname -m)" >&2
    exit 1
fi

# Последний тег релиза на GitHub, без ведущей v
github_latest_version() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -oP '"tag_name":\s*"v?\K[^"]+'
}

install_jetbrains_mono_nerd_font() {
    echo "JetBrainsMono Nerd Font..."

    local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"

    local version
    version=$(github_latest_version ryanoasis/nerd-fonts)
    [[ -n "$version" ]] || { echo "❌ Не определил версию nerd-fonts" >&2; return 1; }
    echo "  последний релиз: v$version"

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    curl -fsSL -o "$tmp/font.zip" \
        "https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/JetBrainsMono.zip"

    # unzip в системе нет, а python3 есть. Заодно фильтруем: из архива нужны
    # только два начертания — обычное и Mono (одноширинные глифы, его хочет
    # kitty). Propo-вариант пропорциональный, в терминале не нужен и только
    # плодит одноимённые семейства в списках шрифтов.
    rm -rf "$font_dir"
    mkdir -p "$font_dir"
    python3 - "$tmp/font.zip" "$font_dir" <<'PY'
import sys, zipfile, os, posixpath

src, dst = sys.argv[1], sys.argv[2]
keep = ("JetBrainsMonoNerdFont-", "JetBrainsMonoNerdFontMono-")
with zipfile.ZipFile(src) as z:
    for name in z.namelist():
        base = posixpath.basename(name)
        if base.endswith(".ttf") and base.startswith(keep):
            with z.open(name) as fsrc, open(os.path.join(dst, base), "wb") as fdst:
                fdst.write(fsrc.read())
PY

    local count
    count=$(find "$font_dir" -name '*.ttf' | wc -l)
    [[ "$count" -gt 0 ]] || { echo "❌ Из архива ничего не распаковалось" >&2; return 1; }

    fc-cache -f "$font_dir" >/dev/null
    echo "  ✅ начертаний: $count, в $font_dir"
}

install_starship() {
    echo "starship..."

    local version
    version=$(github_latest_version starship/starship)
    [[ -n "$version" ]] || { echo "❌ Не определил версию starship" >&2; return 1; }
    echo "  последний релиз: v$version"

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    curl -fsSL -o "$tmp/starship.tar.gz" \
        "https://github.com/starship/starship/releases/download/v${version}/starship-aarch64-unknown-linux-musl.tar.gz"
    tar -xzf "$tmp/starship.tar.gz" -C "$tmp"

    mkdir -p "$BIN_DIR"
    install -m 755 "$tmp/starship" "$BIN_DIR/starship"

    # Проверяем, что бинарник реально запускается на этой машине: неверная арка
    # диагностируется только в момент запуска.
    echo "  ✅ $("$BIN_DIR/starship" --version | head -1)"
}

install_devsy() {
    echo "devsy..."

    mkdir -p "$BIN_DIR"
    curl -fsSL -o "$BIN_DIR/devsy" \
        "https://github.com/devsy-org/devsy/releases/latest/download/devsy-linux-arm64"
    chmod +x "$BIN_DIR/devsy"

    echo "  ✅ devsy $("$BIN_DIR/devsy" --version)"
}

install_starship
install_jetbrains_mono_nerd_font
install_devsy
