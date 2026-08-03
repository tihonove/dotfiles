#!/bin/bash

# Установка dotfiles: симлинки из home/ в домашний каталог.
#
# Всё, что лежит в home/, зеркалит структуру ~:
#   home/.config/foo/bar  -> ~/.config/foo/bar
#   home/.local/bin/baz   -> ~/.local/bin/baz
#
# Линкуются именно ФАЙЛЫ, каталоги создаются обычными. Так в каталогах,
# куда программы пишут своё состояние (~/.config/..., ~/.claude/...),
# под гитом оказывается только то, что мы явно положили в репу.
#
# Исключение — ~/.bashrc. Он НЕ симлинк: в него дописываются корпоративные
# утилиты (обычно PATH), а писать в файл внутри гит-репы им нельзя — это
# грязный git status и молчаливая потеря их строк на git checkout. Вместо
# симлинка сюда один раз дописывается маркированный блок с source
# ~/.config/bash/rc.sh (сам rc.sh — обычный симлинк из home/). Всё, что не
# в блоке, — машинно-локальное, install.sh это не трогает.
#
# Использование:
#   ./install.sh          установить
#   ./install.sh --check  показать, что накопилось в ~/.bashrc вне блока

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$DOTFILES_DIR/home"
TARGET_DIR="$HOME"

BASHRC="$HOME/.bashrc"
BEGIN_MARK='# >>> dotfiles >>>'
END_MARK='# <<< dotfiles <<<'

# Блок, который живёт в ~/.bashrc. Меняется только вместе с проверкой на
# маркер: у тех, кто уже установился, install.sh его не переписывает.
bashrc_block() {
    cat <<EOF
$BEGIN_MARK
# Дописано install.sh из ~/.dotfiles. Руками не править, своё писать НИЖЕ:
# всё, что вне блока, считается машинно-локальным и никуда не уезжает.
[ -f "\$HOME/.config/bash/rc.sh" ] && . "\$HOME/.config/bash/rc.sh"
$END_MARK
EOF
}

# Строки ~/.bashrc за пределами блока — то самое машинно-локальное, ради
# которого вся схема и затевалась. Раз в полгода полезно перечитать и
# решить, что из этого поднять в репу.
bashrc_outside_block() {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        $0 == b { inblock = 1; next }
        $0 == e { inblock = 0; next }
        !inblock && NF { print }
    ' "$BASHRC"
}

check_bashrc() {
    if [[ ! -f "$BASHRC" ]]; then
        echo "~/.bashrc не существует — запусти ./install.sh"
        return
    fi
    if grep -qxF "$BEGIN_MARK" "$BASHRC"; then
        echo "~/.bashrc: блок dotfiles на месте"
    else
        echo "~/.bashrc: блока dotfiles НЕТ — запусти ./install.sh"
    fi

    local extra
    extra="$(bashrc_outside_block)"
    if [[ -z "$extra" ]]; then
        echo "вне блока: пусто"
    else
        echo "вне блока ($(wc -l <<<"$extra") строк):"
        sed 's/^/    /' <<<"$extra"
    fi
}

# Резервная копия существующего файла (симлинки просто удаляем)
backup_if_exists() {
    local target="$1"
    if [[ -L "$target" ]]; then
        rm "$target"
    elif [[ -e "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "  бэкап: $target -> $backup"
        mv "$target" "$backup"
    fi
}

# Идемпотентно: есть маркер — не трогаем, нет — дописываем.
#
# Блок встаёт В НАЧАЛО файла, потому что чужие инсталляторы дописывают
# в конец: так наши настройки грузятся первыми, а их PATH — последним и,
# значит, побеждает при конфликте. Нам это подходит: корпоративные тулзы
# должны работать, а в ~/.local/bin лежит только своё.
ensure_bashrc_block() {
    if [[ -L "$BASHRC" ]]; then
        # Наследство прежней схемы, когда ~/.bashrc был симлинком в репу.
        echo "  ~/.bashrc: убираю симлинк прежней схемы"
        rm "$BASHRC"
    fi

    if [[ -f "$BASHRC" ]] && grep -qxF "$BEGIN_MARK" "$BASHRC"; then
        echo "  ~/.bashrc: блок уже на месте"
        return
    fi

    local tmp="$BASHRC.dotfiles-tmp.$$"
    bashrc_block > "$tmp"
    if [[ -f "$BASHRC" ]]; then
        echo "" >> "$tmp"
        cat "$BASHRC" >> "$tmp"
        cp "$BASHRC" "$BASHRC.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    mv "$tmp" "$BASHRC"
    echo "  ~/.bashrc: блок дописан"
}

case "${1-}" in
    --check)
        check_bashrc
        exit 0
        ;;
    "") ;;
    *)
        echo "usage: ${0##*/} [--check]" >&2
        exit 2
        ;;
esac

echo "Установка dotfiles: $SOURCE_DIR -> $TARGET_DIR"

while IFS= read -r -d '' source_file; do
    rel_path="${source_file#"$SOURCE_DIR"/}"
    target_file="$TARGET_DIR/$rel_path"

    mkdir -p "$(dirname "$target_file")"
    backup_if_exists "$target_file"
    ln -s "$source_file" "$target_file"
    echo "  link: ~/$rel_path"
done < <(find "$SOURCE_DIR" -type f -print0)

ensure_bashrc_block

echo "✅ Готово"
