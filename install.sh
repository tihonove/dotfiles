#!/bin/bash

# Скрипт установки dotfiles
# Создает символические ссылки из .dotfiles в домашний каталог

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="$HOME"

echo "Установка dotfiles из $DOTFILES_DIR в $HOME_DIR"

# Функция для создания резервной копии существующего файла/каталога
backup_if_exists() {
    local target="$1"
    if [[ -e "$target" && ! -L "$target" ]]; then
        local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "  Создаю резервную копию: $target -> $backup"
        mv "$target" "$backup"
    elif [[ -L "$target" ]]; then
        echo "  Удаляю существующую символическую ссылку: $target"
        rm "$target"
    fi
}

# Каталоги в .config, которые линкуются целиком (без рекурсии)
LINK_WHOLE_DIRS=("yazi")

# Функция для линковки файлов в каталоге .config
link_config_files() {
    local source_config="$DOTFILES_DIR/.config"
    local target_config="$HOME_DIR/.config"
    
    if [[ ! -d "$source_config" ]]; then
        return 0
    fi
    
    echo "Обрабатываю каталог .config..."
    
    # Создаем ~/.config если его нет
    if [[ ! -d "$target_config" ]]; then
        echo "  Создаю каталог: $target_config"
        mkdir -p "$target_config"
    fi
    
    # Сначала линкуем каталоги целиком (без рекурсии)
    for dir_name in "${LINK_WHOLE_DIRS[@]}"; do
        local source_dir="$source_config/$dir_name"
        local target_dir="$target_config/$dir_name"
        if [[ -d "$source_dir" ]]; then
            backup_if_exists "$target_dir"
            echo "  Линкую каталог целиком: $dir_name"
            ln -sf "$source_dir" "$target_dir"
        fi
    done
    
    # Проверяем, нужно ли пропускать каталог при рекурсивном обходе
    is_whole_link_dir() {
        local check_path="$1"
        for dir_name in "${LINK_WHOLE_DIRS[@]}"; do
            if [[ "$check_path" == "$source_config/$dir_name" || "$check_path" == "$source_config/$dir_name/"* ]]; then
                return 0
            fi
        done
        return 1
    }
    
    # Рекурсивно обходим остальные файлы и каталоги в .config
    find "$source_config" -type f -o -type d | while read -r item; do
        # Получаем относительный путь от .config
        local rel_path="${item#$source_config/}"
        
        # Пропускаем сам каталог .config
        if [[ "$item" == "$source_config" ]]; then
            continue
        fi
        
        # Пропускаем каталоги, которые линкуются целиком
        if is_whole_link_dir "$item"; then
            continue
        fi
        
        local target_item="$target_config/$rel_path"
        
        if [[ -d "$item" ]]; then
            # Это каталог - создаем его если не существует
            if [[ ! -d "$target_item" ]]; then
                echo "  Создаю каталог: $target_item"
                mkdir -p "$target_item"
            fi
        else
            # Это файл - создаем символическую ссылку
            local target_dir="$(dirname "$target_item")"
            if [[ ! -d "$target_dir" ]]; then
                echo "  Создаю каталог: $target_dir"
                mkdir -p "$target_dir"
            fi
            
            backup_if_exists "$target_item"
            echo "  Линкую файл: $rel_path"
            ln -sf "$item" "$target_item"
        fi
    done
}

# Обрабатываем файлы в корне dotfiles
echo "Обрабатываю файлы в корне dotfiles..."
for item in "$DOTFILES_DIR"/.* "$DOTFILES_DIR"/*; do
    # Получаем имя файла/каталога
    basename="$(basename "$item")"
    
    # Пропускаем специальные файлы и каталоги
    case "$basename" in
        "." | ".." | ".git" | "install.sh" | ".config" | ".fzf")
            continue
            ;;
    esac
    
    # Пропускаем если файл/каталог не существует (из-за глоба)
    if [[ ! -e "$item" ]]; then
        continue
    fi
    
    target="$HOME_DIR/$basename"
    
    # Создаем резервную копию если нужно
    backup_if_exists "$target"
    
    echo "  Линкую: $basename"
    ln -sf "$item" "$target"
done

# Обрабатываем каталог .config отдельно
link_config_files

echo "Установка ble.sh..."
bash .ble-nightly/ble.sh --install ~/.local/share
echo "✅ Установка ble.sh завершена!"

echo "Установка fzf..."
bash "$DOTFILES_DIR/.fzf/install" --key-bindings --completion --update-rc
echo "✅ Установка fzf завершена!"

echo ""
echo "✅ Установка dotfiles завершена!"
echo ""
echo "Созданные символические ссылки:"
echo "  Файлы в корне: ~/.bashrc, ~/.gitconfig, ~/.tmux.conf, etc."
echo "  Файлы конфигурации: ~/.config/alacritty/alacritty.yml, etc."
echo ""
echo "Резервные копии созданы с суффиксом .backup.YYYYMMDD_HHMMSS"