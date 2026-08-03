#!/bin/bash

# Обновление софта, который я сам пишу и на себе же обкатываю.
#
# Отдельно от update-tools.sh нарочно: внешние тулзы обновляются редко и пачкой,
# а своё — часто и по одному. Хочется дёрнуть `update-dogfood.sh` после своей же
# сборки, не трогая starship, шрифты и ble.sh.
#
# Ставим nightly: релизов с версиями нет, тег один и переезжает по коммитам.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"

# Ассет под текущую машину. Вынесено, потому что имена ассетов у всех моих
# проектов одинаковые: <name>-linux-<arch>.
platform_asset_suffix() {
    case "$(uname -m)" in
        aarch64) echo "linux-arm64" ;;
        x86_64)  echo "linux-x64" ;;
        *)       return 1 ;;
    esac
}

# Коммит, на котором собран текущий nightly-релиз. Имя релиза выглядит как
# "Nightly (a791c81)", а `--version` бинарника — как "nightly-a791c81".
# Формат имени — деталь моего же workflow: если он поменяется, вернётся пустая
# строка, и вызывающий просто скачает заново.
github_nightly_commit() {
    curl -fsSL "https://api.github.com/repos/$1/releases/tags/nightly" \
        | grep -oP '"name":\s*"Nightly \(\K[^)]+' || true
}

install_vexx() {
    echo "vexx..."

    local suffix
    suffix=$(platform_asset_suffix) || {
        echo "❌ Нет сборки vexx под $(uname -m)" >&2
        return 1
    }

    local latest current
    latest=$(github_nightly_commit tihonove/vexx)
    current=$("$BIN_DIR/vexx" --version 2>/dev/null || true)

    # Бинарник ~45 МБ, качать его на каждый запуск незачем.
    if [[ -n "$latest" && "$current" == "nightly-$latest" ]]; then
        echo "  ✅ уже актуален: $current"
        return 0
    fi

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    curl -fsSL -o "$tmp/vexx" \
        "https://github.com/tihonove/vexx/releases/download/nightly/vexx-$suffix"

    mkdir -p "$BIN_DIR"
    install -m 755 "$tmp/vexx" "$BIN_DIR/vexx"

    # Заодно проверка, что бинарник запускается на этой машине: неверная арка
    # диагностируется только в момент запуска.
    echo "  ✅ vexx $("$BIN_DIR/vexx" --version)"
}

install_vexx
