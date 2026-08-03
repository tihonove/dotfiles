#!/bin/bash

# Установка dotfiles: симлинки из home/ в домашний каталог.
#
# Всё, что лежит в home/, зеркалит структуру ~:
#   home/.config/foo/bar  -> ~/.config/foo/bar
#   home/.local/bin/baz   -> ~/.local/bin/baz
#
# Линкуются именно ФАЙЛЫ, каталоги создаются обычными. Так в каталогах,
# куда программы пишут своё состояние (~/.config/..., ~/.claude/...),
# под гитом оказывается только то, что мы явно положили в репу. Соседние
# файлы чужих программ не трогаются вовсе.
#
# Исключение — ~/.bashrc. Он НЕ симлинк: в него дописываются корпоративные
# утилиты (обычно PATH), а писать в файл внутри гит-репы им нельзя — это
# грязный git status и молчаливая потеря их строк на git checkout. Вместо
# симлинка сюда один раз дописывается маркированный блок с source
# ~/.config/bash/rc.sh (сам rc.sh — обычный симлинк из home/). Всё, что не
# в блоке, — машинно-локальное, install.sh это не трогает.
#
# Порядок работы: сначала СТРОИТСЯ ПЛАН и проверяется целиком, и только если
# претензий нет — выполняется. Раньше скрипт шёл файл за файлом и на первой же
# коллизии падал с set -e посередине: часть симлинков стоит, часть нет, отката
# нет, сообщение невнятное. Полусломанное состояние хуже честного отказа.
#
# Использование:
#   ./install.sh            установить
#   ./install.sh --dry-run  показать план, ничего не менять
#   ./install.sh --check    показать, что накопилось в ~/.bashrc вне блока

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$DOTFILES_DIR/home"
TARGET_DIR="$HOME"

BASHRC="$HOME/.bashrc"
BEGIN_MARK='# >>> dotfiles >>>'
END_MARK='# <<< dotfiles <<<'

DRY_RUN=0

# ── ~/.bashrc ────────────────────────────────────────────────────────────────

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

# Идемпотентно: есть маркер — не трогаем, нет — дописываем.
#
# Блок встаёт В НАЧАЛО файла, потому что чужие инсталляторы дописывают
# в конец: так наши настройки грузятся первыми, а их PATH — последним и,
# значит, побеждает при конфликте. Нам это подходит: корпоративные тулзы
# должны работать, а в ~/.local/bin лежит только своё.
ensure_bashrc_block() {
    if [[ -L "$BASHRC" ]]; then
        # Наследство прежней схемы, когда ~/.bashrc был симлинком в репу.
        if ((DRY_RUN)); then
            echo "  ~/.bashrc: убрал бы симлинк прежней схемы"
        else
            echo "  ~/.bashrc: убираю симлинк прежней схемы"
            rm "$BASHRC"
        fi
    fi

    if [[ -f "$BASHRC" ]] && grep -qxF "$BEGIN_MARK" "$BASHRC"; then
        echo "  ~/.bashrc: блок уже на месте"
        return
    fi

    if ((DRY_RUN)); then
        echo "  ~/.bashrc: дописал бы блок в начало файла"
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

# ── План ─────────────────────────────────────────────────────────────────────

declare -a PLAN_REL=()

build_plan() {
    local f
    while IFS= read -r -d '' f; do
        PLAN_REL+=("${f#"$SOURCE_DIR"/}")
    done < <(find "$SOURCE_DIR" -type f -print0 | sort -z)

    [[ ${#PLAN_REL[@]} -gt 0 ]] || { echo "❌ В $SOURCE_DIR нет файлов" >&2; exit 1; }
}

# Что произойдёт с конкретным файлом. Отдельный статус для «уже правильный
# симлинк» не косметика: раньше скрипт сносил и пересоздавал КАЖДЫЙ симлинк на
# каждом запуске, и по выводу нельзя было понять, что реально изменилось.
file_status() {
    local rel="$1" target="$TARGET_DIR/$rel" src="$SOURCE_DIR/$rel"

    if [[ -L "$target" ]]; then
        if [[ "$(readlink -- "$target")" == "$src" ]]; then
            echo ok          # уже указывает куда надо
        else
            echo relink      # симлинк, но не туда
        fi
    elif [[ -e "$target" ]]; then
        echo backup          # обычный файл — унести в бэкап
    else
        echo new
    fi
}

# ── Предполётная проверка ────────────────────────────────────────────────────
#
# Ищем всё, обо что установка споткнётся или что она молча испортит. Ничего не
# меняем: задача — либо разрешить установку целиком, либо честно отказать.

declare -a ERRORS=() WARNINGS=()
declare -A SEEN_PATH=()

short() { echo "~${1#"$HOME"}"; }

preflight() {
    local rel target dir acc comp
    local -a parts

    for rel in "${PLAN_REL[@]}"; do
        target="$TARGET_DIR/$rel"

        # 1. Каждый компонент пути должен быть каталогом (или отсутствовать).
        #    Если там лежит файл — mkdir -p упадёт. Раньше это случалось уже
        #    в процессе установки, на середине.
        dir="${rel%/*}"
        [[ "$dir" == "$rel" ]] && dir=""     # файл прямо в home/
        if [[ -n "$dir" ]]; then
            acc="$TARGET_DIR"
            IFS=/ read -ra parts <<< "$dir"
            for comp in "${parts[@]}"; do
                acc="$acc/$comp"
                [[ -n "${SEEN_PATH[$acc]-}" ]] && continue
                SEEN_PATH[$acc]=1

                if [[ -e "$acc" && ! -d "$acc" ]]; then
                    ERRORS+=("$(short "$acc") — не каталог, а на нём должен лежать путь к $(short "$target")")
                elif [[ -L "$acc" ]]; then
                    WARNINGS+=("$(short "$acc") — симлинк на каталог, файлы лягут в $(readlink -f -- "$acc")")
                fi
            done
        fi

        # 2. Каталог на месте файла. backup_if_exists унёс бы его ЦЕЛИКОМ в
        #    .backup.TIMESTAMP — данные не пропадут, но приложение сломается
        #    молча. Такое решение принимает человек, не скрипт.
        if [[ ! -L "$target" && -d "$target" ]]; then
            ERRORS+=("$(short "$target") — существующий КАТАЛОГ на месте файла; перенеси или удали его сам")
        fi
    done

    # 3. ~/.bashrc должен быть файлом или симлинком, но не каталогом.
    if [[ -d "$BASHRC" && ! -L "$BASHRC" ]]; then
        ERRORS+=("~/.bashrc — каталог; разбирайся руками")
    fi

    # 4. Симлинки внутри home/ find -type f не видит, и они молча не поедут.
    local link
    while IFS= read -r -d '' link; do
        WARNINGS+=("home/${link#"$SOURCE_DIR"/} — симлинк, установлен НЕ будет (линкуются только обычные файлы)")
    done < <(find "$SOURCE_DIR" -type l -print0)

    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        printf '⚠  %s\n' "${WARNINGS[@]}"
        echo
    fi

    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        {
            echo "❌ Установка не начата — сначала разберись с этим:"
            printf '   • %s\n' "${ERRORS[@]}"
            echo
            echo "   Ничего не изменено. После правки запусти ./install.sh --dry-run."
        } >&2
        exit 1
    fi
}

# ── Установка ────────────────────────────────────────────────────────────────

install_plan() {
    local rel target src status
    local n_ok=0 n_new=0 n_relink=0 n_backup=0

    for rel in "${PLAN_REL[@]}"; do
        target="$TARGET_DIR/$rel"
        src="$SOURCE_DIR/$rel"
        status="$(file_status "$rel")"

        case "$status" in
            # Постинкремент ((n++)) тут нельзя: при n=0 он возвращает 1, и
            # set -e убивает скрипт на первом же файле.
            ok)
                n_ok=$((n_ok + 1))
                ((DRY_RUN)) && echo "  =    ~/$rel"
                continue
                ;;
            new)    n_new=$((n_new + 1))       ;;
            relink) n_relink=$((n_relink + 1)) ;;
            backup) n_backup=$((n_backup + 1)) ;;
        esac

        if ((DRY_RUN)); then
            case "$status" in
                new)    echo "  link ~/$rel" ;;
                relink) echo "  link ~/$rel  (сейчас указывает на $(readlink -- "$target"))" ;;
                backup) echo "  link ~/$rel  (существующий файл уедет в .backup.*)" ;;
            esac
            continue
        fi

        mkdir -p "$(dirname "$target")"
        if [[ "$status" == backup ]]; then
            local backup="$target.backup.$(date +%Y%m%d_%H%M%S)"
            echo "  бэкап: ~/$rel -> $(basename "$backup")"
            mv "$target" "$backup"
        elif [[ "$status" == relink ]]; then
            rm "$target"
        fi
        ln -s "$src" "$target"
        echo "  link ~/$rel"
    done

    echo
    echo "  файлов: $((${#PLAN_REL[@]})) — на месте $n_ok, новых $n_new, перелинковано $n_relink, с бэкапом $n_backup"
}

# ── Точка входа ──────────────────────────────────────────────────────────────

case "${1-}" in
    --check)
        check_bashrc
        exit 0
        ;;
    --dry-run)
        DRY_RUN=1
        ;;
    "") ;;
    *)
        echo "usage: ${0##*/} [--dry-run|--check]" >&2
        exit 2
        ;;
esac

if ((DRY_RUN)); then
    echo "План установки (ничего не меняется): $SOURCE_DIR -> $TARGET_DIR"
else
    echo "Установка dotfiles: $SOURCE_DIR -> $TARGET_DIR"
fi
echo

build_plan
preflight
install_plan
ensure_bashrc_block

echo
((DRY_RUN)) && echo "✅ План проверен, изменений не вносилось" || echo "✅ Готово"
