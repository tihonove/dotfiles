#!/bin/bash

# Установка dotfiles: симлинки из модулей в домашний каталог.
#
# Payload разложен по модулям. Всё, что лежит в home/ модуля, зеркалит ~:
#   modules/core/home/.config/foo/bar -> ~/.config/foo/bar
#   modules/core/home/.local/bin/baz  -> ~/.local/bin/baz
#
# Цель считается от пути ВНУТРИ home/, а не от имени модуля. Поэтому файл можно
# двигать между модулями сколько угодно — для системы это no-op, симлинк остаётся
# тем же. Модули режут репу, а не расположение файлов в ~.
#
# Линкуются именно ФАЙЛЫ, каталоги создаются обычными. Так в каталогах,
# куда программы пишут своё состояние (~/.config/..., ~/.claude/...),
# под гитом оказывается только то, что мы явно положили в репу. Соседние
# файлы чужих программ не трогаются вовсе.
#
# Какие модули ставить, решает профиль ~/.config/dotfiles/profile — файл ВНЕ репы,
# по той же конвенции, что ~/.ssh/config.d/*.conf и ~/.config/devsy-setup.conf:
# машинно-специфичное не уезжает в публичную репу. Нет профиля — ставится один
# core. Доустановка подсистем — руками: ./install.sh add <модуль>.
#
# Исключение — ~/.bashrc. Он НЕ симлинк: в него дописываются корпоративные
# утилиты (обычно PATH), а писать в файл внутри гит-репы им нельзя — это
# грязный git status и молчаливая потеря их строк на git checkout. Вместо
# симлинка сюда один раз дописывается маркированный блок с source
# ~/.config/bash/rc.sh (сам rc.sh — обычный симлинк из модуля). Всё, что не
# в блоке, — машинно-локальное, install.sh это не трогает.
#
# Порядок работы: сначала СТРОИТСЯ ПЛАН и проверяется целиком, и только если
# претензий нет — выполняется. Раньше скрипт шёл файл за файлом и на первой же
# коллизии падал с set -e посередине: часть симлинков стоит, часть нет, отката
# нет, сообщение невнятное. Полусломанное состояние хуже честного отказа.
#
# Использование:
#   ./install.sh              установить включённые модули
#   ./install.sh --dry-run    показать план, ничего не менять
#   ./install.sh list         какие модули есть и что включено
#   ./install.sh add <мод>    включить модуль в профиле и установить
#   ./install.sh remove <мод> выключить модуль в профиле
#   ./install.sh --check      показать, что накопилось в ~/.bashrc вне блока

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$DOTFILES_DIR/modules"
TARGET_DIR="$HOME"

PROFILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"

BASHRC="$HOME/.bashrc"
BEGIN_MARK='# >>> dotfiles >>>'
END_MARK='# <<< dotfiles <<<'
LATE_BEGIN_MARK='# >>> dotfiles prompt >>>'
LATE_END_MARK='# <<< dotfiles prompt <<<'

DRY_RUN=0

short() { echo "~${1#"$HOME"}"; }

# ── Модули ───────────────────────────────────────────────────────────────────

# core включён всегда и идёт первым: это база, без которой остальное не имеет
# смысла, и держать её в профиле — лишний способ отстрелить себе ногу.
declare -a MODULES=()

read_profile() {
    local line
    local -A seen=()

    MODULES=(core)
    seen[core]=1

    [[ -f "$PROFILE" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"   # trim слева
        line="${line%"${line##*[![:space:]]}"}"   # trim справа
        [[ -n "$line" ]] || continue
        [[ -n "${seen[$line]-}" ]] && continue
        seen[$line]=1
        MODULES+=("$line")
    done < "$PROFILE"
}

# Метаданные модуля. module.conf — свой файл в своей репе, поэтому просто
# подключается через `.`; переменные сбрасываются перед каждым модулем, чтобы
# отсутствующий ключ не подхватил значение от предыдущего.
MOD_DESC=""
MOD_REQUIRES=""
MOD_SCRIPTS=""

module_meta() {
    local conf="$MODULES_DIR/$1/module.conf"
    local desc="" requires="" scripts=""

    if [[ -f "$conf" ]]; then
        # shellcheck disable=SC1090
        . "$conf"
    fi

    MOD_DESC="$desc"
    MOD_REQUIRES="$requires"
    MOD_SCRIPTS="$scripts"
}

# Чего из requires нет в системе. Пустой вывод — всё на месте.
module_missing_cmds() {
    local cmd out=""
    module_meta "$1"
    for cmd in $MOD_REQUIRES; do
        command -v "$cmd" >/dev/null 2>&1 || out+=" $cmd"
    done
    echo "${out# }"
}

list_modules() {
    local dir m mm s enabled missing mark scripts

    if [[ -f "$PROFILE" ]]; then
        echo "Профиль: $(short "$PROFILE")"
    else
        echo "Профиль: $(short "$PROFILE") — нет, включён только core"
    fi
    echo

    for dir in "$MODULES_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        m="$(basename "$dir")"

        enabled=0
        for mm in "${MODULES[@]}"; do
            [[ "$mm" == "$m" ]] && { enabled=1; break; }
        done

        module_meta "$m"
        mark="·"
        ((enabled)) && mark="✓"

        # Забираем до вызова module_missing_cmds: он внутри дёргает module_meta
        # и затирает MOD_*.
        scripts="$MOD_SCRIPTS"

        printf '  %s %-10s %s\n' "$mark" "$m" "$MOD_DESC"

        missing="$(module_missing_cmds "$m")"
        if [[ -n "$missing" ]]; then
            printf '    %-10s   нет в системе: %s\n' "" "$missing"
        fi

        # Скрипты модуля install.sh НЕ запускает — только показывает. Он
        # раскладывает симлинки, а не выполняет произвольный код с сетью и sudo.
        for s in $scripts; do
            printf '    %-10s   скрипт: modules/%s/%s\n' "" "$m" "$s"
        done
    done

    # Модуль в профиле, которого нет в репе, иначе просто не показался бы.
    for m in "${MODULES[@]}"; do
        [[ -d "$MODULES_DIR/$m" ]] || printf '  ✗ %-10s НЕТ ТАКОГО МОДУЛЯ (есть в профиле)\n' "$m"
    done
}

# Правка профиля. Симлинки при remove НЕ снимаются: молча удалять файлы из ~
# скрипт не должен, поэтому он только показывает, что осталось.
profile_add() {
    local mod="$1"

    if [[ ! -d "$MODULES_DIR/$mod" ]]; then
        echo "❌ Нет модуля «$mod». Список: ./install.sh list" >&2
        exit 1
    fi

    for m in "${MODULES[@]}"; do
        if [[ "$m" == "$mod" ]]; then
            echo "  модуль «$mod» уже включён"
            return
        fi
    done

    mkdir -p "$(dirname "$PROFILE")"
    if [[ ! -f "$PROFILE" ]]; then
        cat > "$PROFILE" <<'EOF'
# Какие модули dotfiles ставить на этой машине. Имя модуля на строку.
# core включён всегда, перечислять его не нужно.
EOF
    fi
    echo "$mod" >> "$PROFILE"
    echo "  модуль «$mod» включён в $(short "$PROFILE")"
}

profile_remove() {
    local mod="$1" tmp rel

    if [[ "$mod" == core ]]; then
        echo "❌ core выключить нельзя — это база." >&2
        exit 1
    fi

    if [[ ! -f "$PROFILE" ]] || ! grep -qxF "$mod" "$PROFILE"; then
        echo "  модуль «$mod» и так не включён"
        return
    fi

    # `|| true`: если после удаления строк не осталось вовсе, grep возвращает 1,
    # и set -e убил бы скрипт молча — профиль остался бы нетронутым.
    tmp="$PROFILE.tmp.$$"
    grep -vxF "$mod" "$PROFILE" > "$tmp" || true
    mv "$tmp" "$PROFILE"
    echo "  модуль «$mod» выключен в $(short "$PROFILE")"

    if [[ -d "$MODULES_DIR/$mod/home" ]]; then
        echo
        echo "  Симлинки не сняты — проверь и убери сам, если они больше не нужны:"
        while IFS= read -r -d '' f; do
            rel="${f#"$MODULES_DIR/$mod/home"/}"
            [[ -L "$TARGET_DIR/$rel" ]] && echo "    rm ~/$rel"
        done < <(find "$MODULES_DIR/$mod/home" -type f -print0 | sort -z)
    fi
}

# ── ~/.bashrc ────────────────────────────────────────────────────────────────

# Блоков ДВА, и это не симметрия ради красоты, а разные требования к порядку.
#
# Ранний идёт в НАЧАЛО: чужие инсталляторы дописывают себя в конец, и их PATH
# должен лечь позже нашего, чтобы побеждать при конфликте имён.
#
# Поздний идёт в КОНЕЦ, и ровно по обратной причине. Чужой ~/.bashrc может
# задавать свой PS1 ниже нашего блока — так делает базовый образ devcontainer
# (функция __bash_prompt). Пока промпт настраивался в раннем блоке, starship
# отрабатывал первым и его молча затирали: со стороны выглядело, будто starship
# не установлен вовсе.
#
# Оба меняются только вместе с проверкой на свой маркер: у тех, кто уже
# установился, install.sh их не переписывает.
bashrc_block_early() {
    cat <<EOF
$BEGIN_MARK
# Дописано install.sh из ~/.dotfiles. Руками не править, своё писать МЕЖДУ
# блоками: всё, что вне них, считается машинно-локальным и никуда не уезжает.
[ -f "\$HOME/.config/bash/rc.sh" ] && . "\$HOME/.config/bash/rc.sh"
$END_MARK
EOF
}

bashrc_block_late() {
    cat <<EOF
$LATE_BEGIN_MARK
# Промпт — последним, ПОСЛЕ всего остального в этом файле: иначе чужой PS1,
# заданный ниже, затрёт starship. Подробности — в самом prompt.sh.
[ -f "\$HOME/.config/bash/prompt.sh" ] && . "\$HOME/.config/bash/prompt.sh"
$LATE_END_MARK
EOF
}

# Строки ~/.bashrc за пределами блоков — то самое машинно-локальное, ради
# которого вся схема и затевалась. Раз в полгода полезно перечитать и
# решить, что из этого поднять в репу.
bashrc_outside_block() {
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" \
        -v lb="$LATE_BEGIN_MARK" -v le="$LATE_END_MARK" '
        $0 == b || $0 == lb { inblock = 1; next }
        $0 == e || $0 == le { inblock = 0; next }
        !inblock && NF { print }
    ' "$BASHRC"
}

check_bashrc() {
    echo "Модули: ${MODULES[*]}"
    echo

    if [[ ! -f "$BASHRC" ]]; then
        echo "~/.bashrc не существует — запусти ./install.sh"
        return
    fi
    local m
    for m in "$BEGIN_MARK:ранний (rc.sh)" "$LATE_BEGIN_MARK:поздний (prompt.sh)"; do
        if grep -qxF "${m%%:*}" "$BASHRC"; then
            echo "~/.bashrc: блок ${m#*:} на месте"
        else
            echo "~/.bashrc: блока ${m#*:} НЕТ — запусти ./install.sh"
        fi
    done

    local extra
    extra="$(bashrc_outside_block)"
    if [[ -z "$extra" ]]; then
        echo "вне блоков: пусто"
    else
        echo "вне блоков ($(wc -l <<<"$extra") строк):"
        sed 's/^/    /' <<<"$extra"
    fi
}

# Идемпотентно: есть маркер — не трогаем, нет — дописываем. Бэкап снимается
# один раз на запуск, даже если дописываются оба блока.
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

    local backed_up=0 tmp

    backup_once() {
        ((backed_up)) && return 0
        [[ -f "$BASHRC" ]] || return 0
        cp "$BASHRC" "$BASHRC.backup.$(date +%Y%m%d_%H%M%S)"
        backed_up=1
    }

    # Ранний блок — в начало файла.
    if [[ -f "$BASHRC" ]] && grep -qxF "$BEGIN_MARK" "$BASHRC"; then
        echo "  ~/.bashrc: ранний блок уже на месте"
    elif ((DRY_RUN)); then
        echo "  ~/.bashrc: дописал бы ранний блок в начало файла"
    else
        tmp="$BASHRC.dotfiles-tmp.$$"
        bashrc_block_early > "$tmp"
        if [[ -f "$BASHRC" ]]; then
            echo "" >> "$tmp"
            cat "$BASHRC" >> "$tmp"
            backup_once
        fi
        mv "$tmp" "$BASHRC"
        echo "  ~/.bashrc: ранний блок дописан"
    fi

    # Поздний блок — в конец. Именно в конец, а не рядом с ранним: смысл всей
    # затеи в том, чтобы промпт настраивался после чужих строк.
    if [[ -f "$BASHRC" ]] && grep -qxF "$LATE_BEGIN_MARK" "$BASHRC"; then
        echo "  ~/.bashrc: поздний блок уже на месте"
    elif ((DRY_RUN)); then
        echo "  ~/.bashrc: дописал бы поздний блок в конец файла"
    else
        backup_once
        { echo ""; bashrc_block_late; } >> "$BASHRC"
        echo "  ~/.bashrc: поздний блок дописан"
    fi

    unset -f backup_once
}

# ── План ─────────────────────────────────────────────────────────────────────

# Три параллельных массива: путь относительно home/ (он же цель в ~), источник
# и модуль, из которого файл приехал. Источник теперь у каждого файла свой,
# одной константой SOURCE_DIR больше не обойтись.
declare -a PLAN_REL=() PLAN_SRC=() PLAN_MOD=()

build_plan() {
    local m src f

    for m in "${MODULES[@]}"; do
        src="$MODULES_DIR/$m/home"
        # Несуществующий модуль и модуль без home/ — забота preflight, здесь
        # просто нечего добавить.
        [[ -d "$src" ]] || continue
        while IFS= read -r -d '' f; do
            PLAN_REL+=("${f#"$src"/}")
            PLAN_SRC+=("$f")
            PLAN_MOD+=("$m")
        done < <(find "$src" -type f -print0 | sort -z)
    done

    [[ ${#PLAN_REL[@]} -gt 0 ]] || { echo "❌ Включённые модули не дали ни одного файла" >&2; exit 1; }
}

# Что произойдёт с конкретным файлом. Отдельный статус для «уже правильный
# симлинк» не косметика: раньше скрипт сносил и пересоздавал КАЖДЫЙ симлинк на
# каждом запуске, и по выводу нельзя было понять, что реально изменилось.
file_status() {
    local rel="$1" src="$2" target="$TARGET_DIR/$1"

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

preflight() {
    local i m rel target dir acc comp missing owner
    local -a parts
    local -A rel_owner=()

    # 0. Модули: существование и требования к системе. Требования проверяются
    #    ДО файлов, потому что «поставил конфиг sway на машину без sway» — это
    #    не ошибка файловой системы, а бессмысленная установка.
    for m in "${MODULES[@]}"; do
        if [[ ! -d "$MODULES_DIR/$m" ]]; then
            ERRORS+=("модуль «$m» из профиля не существует; список — ./install.sh list")
            continue
        fi
        # Модуль без home/ подозрителен, только если он и скриптов не объявил.
        # Модуль вроде vexx — это ровно скрипт и ничего больше, и ругаться на
        # него на каждой установке значит приучить не читать предупреждения.
        module_meta "$m"
        [[ -d "$MODULES_DIR/$m/home" || -n "$MOD_SCRIPTS" ]] ||
            WARNINGS+=("модуль «$m» не содержит ни home/, ни scripts — ничего не делает")

        missing="$(module_missing_cmds "$m")"
        [[ -z "$missing" ]] ||
            ERRORS+=("модуль «$m»: в системе нет — $missing; поставь их или убери модуль: ./install.sh remove $m")
    done

    for i in "${!PLAN_REL[@]}"; do
        rel="${PLAN_REL[$i]}"
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

        # 3. Два модуля на одну цель. До модулей такое было невозможно, теперь
        #    возможно, и порядок установки решал бы исход молча.
        owner="${rel_owner[$rel]-}"
        if [[ -n "$owner" ]]; then
            ERRORS+=("~/$rel дают сразу два модуля: «$owner» и «${PLAN_MOD[$i]}»")
        else
            rel_owner[$rel]="${PLAN_MOD[$i]}"
        fi
    done

    # 4. ~/.bashrc должен быть файлом или симлинком, но не каталогом.
    if [[ -d "$BASHRC" && ! -L "$BASHRC" ]]; then
        ERRORS+=("~/.bashrc — каталог; разбирайся руками")
    fi

    # 5. Симлинки внутри home/ find -type f не видит, и они молча не поедут.
    local link
    for m in "${MODULES[@]}"; do
        [[ -d "$MODULES_DIR/$m/home" ]] || continue
        while IFS= read -r -d '' link; do
            WARNINGS+=("$m: ${link#"$MODULES_DIR/$m/home"/} — симлинк, установлен НЕ будет (линкуются только обычные файлы)")
        done < <(find "$MODULES_DIR/$m/home" -type l -print0)
    done

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
    local i rel src target status cur_mod=""
    local n_ok=0 n_new=0 n_relink=0 n_backup=0

    for i in "${!PLAN_REL[@]}"; do
        rel="${PLAN_REL[$i]}"
        src="${PLAN_SRC[$i]}"
        target="$TARGET_DIR/$rel"
        status="$(file_status "$rel" "$src")"

        # Заголовок модуля — только если под ним что-то будет напечатано. Иначе
        # при обычном запуске (где строки для ok не выводятся) модуль, где всё
        # на месте, давал бы пустой заголовок.
        if [[ "${PLAN_MOD[$i]}" != "$cur_mod" ]] && { ((DRY_RUN)) || [[ "$status" != ok ]]; }; then
            cur_mod="${PLAN_MOD[$i]}"
            echo "  [$cur_mod]"
        fi

        case "$status" in
            # Постинкремент ((n++)) тут нельзя: при n=0 он возвращает 1, и
            # set -e убивает скрипт на первом же файле.
            ok)
                n_ok=$((n_ok + 1))
                ((DRY_RUN)) && echo "    =    ~/$rel"
                continue
                ;;
            new)    n_new=$((n_new + 1))       ;;
            relink) n_relink=$((n_relink + 1)) ;;
            backup) n_backup=$((n_backup + 1)) ;;
        esac

        if ((DRY_RUN)); then
            case "$status" in
                new)    echo "    link ~/$rel" ;;
                relink) echo "    link ~/$rel  (сейчас указывает на $(readlink -- "$target"))" ;;
                backup) echo "    link ~/$rel  (существующий файл уедет в .backup.*)" ;;
            esac
            continue
        fi

        mkdir -p "$(dirname "$target")"
        if [[ "$status" == backup ]]; then
            local backup="$target.backup.$(date +%Y%m%d_%H%M%S)"
            echo "    бэкап: ~/$rel -> $(basename "$backup")"
            mv "$target" "$backup"
        elif [[ "$status" == relink ]]; then
            rm "$target"
        fi
        ln -s "$src" "$target"
        echo "    link ~/$rel"
    done

    echo
    echo "  файлов: $((${#PLAN_REL[@]})) — на месте $n_ok, новых $n_new, перелинковано $n_relink, с бэкапом $n_backup"
}

# ── Точка входа ──────────────────────────────────────────────────────────────

case "${1-}" in
    --check)
        read_profile
        check_bashrc
        exit 0
        ;;
    list)
        read_profile
        list_modules
        exit 0
        ;;
    add)
        [[ -n "${2-}" ]] || { echo "usage: ${0##*/} add <модуль>" >&2; exit 2; }
        read_profile
        profile_add "$2"
        read_profile          # перечитать: план строится уже с новым модулем
        echo
        ;;
    remove)
        [[ -n "${2-}" ]] || { echo "usage: ${0##*/} remove <модуль>" >&2; exit 2; }
        read_profile
        profile_remove "$2"
        exit 0
        ;;
    --dry-run)
        DRY_RUN=1
        read_profile
        ;;
    "")
        read_profile
        ;;
    *)
        echo "usage: ${0##*/} [--dry-run|--check|list|add <мод>|remove <мод>]" >&2
        exit 2
        ;;
esac

if ((DRY_RUN)); then
    echo "План установки (ничего не меняется): модули ${MODULES[*]} -> $TARGET_DIR"
else
    echo "Установка dotfiles: модули ${MODULES[*]} -> $TARGET_DIR"
fi
echo

build_plan
preflight
install_plan
ensure_bashrc_block

echo
((DRY_RUN)) && echo "✅ План проверен, изменений не вносилось" || echo "✅ Готово"
