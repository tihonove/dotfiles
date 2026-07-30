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

install_starship
