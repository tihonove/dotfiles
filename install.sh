#!/bin/bash

# Установка dotfiles: симлинки из home/ в домашний каталог.
#
# Всё, что лежит в home/, зеркалит структуру ~:
#   home/.bashrc          -> ~/.bashrc
#   home/.config/foo/bar  -> ~/.config/foo/bar
#
# Линкуются именно ФАЙЛЫ, каталоги создаются обычными. Так в каталогах,
# куда программы пишут своё состояние (~/.config/..., ~/.claude/...),
# под гитом оказывается только то, что мы явно положили в репу.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$DOTFILES_DIR/home"
TARGET_DIR="$HOME"

echo "Установка dotfiles: $SOURCE_DIR -> $TARGET_DIR"

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

while IFS= read -r -d '' source_file; do
    rel_path="${source_file#"$SOURCE_DIR"/}"
    target_file="$TARGET_DIR/$rel_path"

    mkdir -p "$(dirname "$target_file")"
    backup_if_exists "$target_file"
    ln -s "$source_file" "$target_file"
    echo "  link: ~/$rel_path"
done < <(find "$SOURCE_DIR" -type f -print0)

echo "✅ Готово"
