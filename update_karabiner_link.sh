#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SOURCE_FILE="$HOME/.dotfiles/.config/karabiner/karabiner.json"
TARGET_FILE="$HOME/.config/karabiner/karabiner.json"

# Проверяем наличие исходного файла
if [ ! -f "$SOURCE_FILE" ]; then
    echo -e "${RED}❌ Файл $SOURCE_FILE не найден${NC}"
    exit 1
fi

# Создаем директорию если не существует
mkdir -p "$HOME/.config/karabiner"

# Удаляем существующий файл или симлинк
if [ -e "$TARGET_FILE" ] || [ -L "$TARGET_FILE" ]; then
    rm "$TARGET_FILE"
    echo "🗑️  Удален существующий файл"
fi

# Создаем симлинк
ln -s "$SOURCE_FILE" "$TARGET_FILE"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Симлинк успешно создан${NC}"
    echo "   $TARGET_FILE -> $SOURCE_FILE"
else
    echo -e "${RED}❌ Ошибка при создании симлинка${NC}"
    exit 1
fi