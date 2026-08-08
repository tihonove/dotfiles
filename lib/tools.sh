# Общее для установщиков внешних тулзов (modules/*/update).
#
# Подключается через `.`, своих действий не выполняет. Лежит в lib/, а не в
# modules/: install.sh считает модулем каждый каталог в modules/, и библиотека
# показалась бы в ./install.sh list отдельной строкой.

BIN_DIR="$HOME/.local/bin"

have() { command -v "$1" >/dev/null 2>&1; }

# Последний тег релиза на GitHub, без ведущей v
github_latest_version() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -oP '"tag_name":\s*"v?\K[^"]+'
}

# Архитектура в том виде, в каком её называет конкретный проект. Проверка нужна
# не всем: шрифты и ble.sh от архитектуры не зависят вовсе, а раньше весь
# update-tools.sh падал на aarch64-гарде в первой же строке и не ставил ничего.
#
#   arch_for rust   -> aarch64-unknown-linux-musl | x86_64-unknown-linux-musl
#   arch_for go     -> linux-arm64 | linux-amd64
#   arch_for plain  -> arm64 | amd64      (так называет ассеты fzf)
arch_for() {
    local kind="$1" m
    m="$(uname -m)"
    case "$kind:$m" in
        rust:aarch64)  echo aarch64-unknown-linux-musl ;;
        rust:x86_64)   echo x86_64-unknown-linux-musl  ;;
        # GOARCH для x86_64 — amd64, «x64» в Go-мире не бывает вовсе. Ошибка не
        # всплывала, потому что единственный потребитель (devsy) ставился только
        # на aarch64, где вторая строка случайно верна.
        go:aarch64)    echo linux-arm64 ;;
        go:x86_64)     echo linux-amd64 ;;
        plain:aarch64) echo arm64 ;;
        plain:x86_64)  echo amd64 ;;
        *) echo "❌ Неизвестная архитектура: $m" >&2; return 1 ;;
    esac
}
