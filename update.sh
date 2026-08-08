#!/bin/bash

# Обновление dotfiles на машине: подтянуть репу и привести раскладку в
# соответствие с новым содержимым.
#
# Почему это не `git pull && ./install.sh`. Почти — да: install.sh идемпотентен
# и сам перезапускает установщики тулов. Не закрывает он ровно один случай —
# файл, УДАЛЁННЫЙ из репы. Его симлинк в ~ после pull повисает битым и остаётся
# таким навсегда: install.sh строит план по текущим деревьям модулей и на
# исчезнувший путь больше не заходит, uninstall.sh обходит их же. Тот же класс
# мусора, ради которого написан uninstall.sh, только с другой стороны.
#
# Устаревшее ищется ПО ДАННЫМ GIT, а не обходом ~. `git diff --name-status` между
# старым и новым HEAD даёт удалённые пути точно и мгновенно, тогда как обход
# домашнего каталога и медленнее, и опаснее: битых симлинков там хватает и без
# нас (Chrome, pulse), а git знает ровно наши.
#
# Правило удаления то же, что в uninstall.sh: снимается только симлинк,
# указывающий ровно на наш путь в репе. Файл, переехавший между модулями, тоже
# приходит сюда как удалённый — симлинк снимается, а install.sh следом линкует
# его по новому адресу.
#
# Использование:
#   ./update.sh              подтянуть и обновить раскладку
#   ./update.sh --dry-run    показать, что приедет и что снимется
#   ./update.sh --no-tools   не перезапускать установщики тулов модулей

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$DOTFILES_DIR/modules"
TARGET_DIR="$HOME"

DRY_RUN=0
declare -a INSTALL_ARGS=()

short() { echo "~${1#"$HOME"}"; }

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=1; INSTALL_ARGS+=("$arg") ;;
        --no-tools) INSTALL_ARGS+=("$arg") ;;
        *) echo "usage: ${0##*/} [--dry-run] [--no-tools]" >&2; exit 2 ;;
    esac
done

cd "$DOTFILES_DIR"

# ── Предполётная проверка ────────────────────────────────────────────────────
#
# Отказываем ДО всякого действия, по тому же принципу, что preflight в
# install.sh: либо обновление проходит целиком, либо не начинается вовсе.

if [[ ! -d .git ]]; then
    echo "❌ $(short "$DOTFILES_DIR") — не git-репозиторий, обновлять нечего" >&2
    exit 1
fi

# Только ОТСЛЕЖИВАЕМЫЕ правки: именно из-за них pull падает посреди работы.
# Неотслеживаемые файлы ему не мешают вовсе — кроме случая, когда входящий
# коммит добавляет файл с тем же именем, и тогда git сам откажется с внятным
# сообщением. Блокировать из-за забытого черновика в корне репы значило бы
# сделать скрипт неприменимым ровно тогда, когда он нужен.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    {
        echo "❌ В репе есть незакоммиченные изменения — pull их не переживёт:"
        git status --short --untracked-files=no | sed 's/^/   /'
        echo
        echo "   Закоммить или отложи (git stash), потом запусти снова."
    } >&2
    exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    echo "❌ У ветки «$BRANCH» нет upstream — откуда тянуть, неизвестно" >&2
    exit 1
fi

OLD_HEAD="$(git rev-parse HEAD)"

# ── Забираем новое ───────────────────────────────────────────────────────────

echo "Обновление dotfiles: $(short "$DOTFILES_DIR") (ветка $BRANCH)"
((DRY_RUN)) && echo "(--dry-run: ничего не меняется)"
echo

# --ff-only намеренно: разошедшиеся ветки — повод разобраться руками, а не
# молча получить merge-коммит в конфигах.
if ((DRY_RUN)); then
    git fetch --quiet
    NEW_HEAD="$(git rev-parse '@{u}')"
    if ! git merge-base --is-ancestor "$OLD_HEAD" "$NEW_HEAD"; then
        echo "❌ Ветки разошлись — обновить перемоткой не выйдет, разбирайся руками" >&2
        exit 1
    fi
else
    git pull --ff-only --quiet
    NEW_HEAD="$(git rev-parse HEAD)"
fi

if [[ "$OLD_HEAD" == "$NEW_HEAD" ]]; then
    echo "  репа: изменений нет"
else
    echo "  репа: $(git rev-list --count "$OLD_HEAD..$NEW_HEAD") новых коммитов"
    git log --oneline --no-decorate "$OLD_HEAD..$NEW_HEAD" | sed 's/^/    /'
fi
echo

# ── Снятие устаревшего ───────────────────────────────────────────────────────
#
# Удалённые файлы модулей: modules/<мод>/home/<rel> -> ~/<rel>.

declare -a STALE=()

collect_stale() {
    local path rel target m

    [[ "$OLD_HEAD" != "$NEW_HEAD" ]] || return 0

    while IFS= read -r path; do
        # modules/<мод>/home/<rel>: отрезаем два первых компонента и home/
        [[ "$path" == modules/*/home/* ]] || continue
        rel="${path#modules/*/home/}"
        m="${path#modules/}"; m="${m%%/*}"
        target="$TARGET_DIR/$rel"

        # Снимаем, только если это симлинк ровно на исчезнувший файл.
        if [[ -L "$target" ]] && [[ "$(readlink -- "$target")" == "$DOTFILES_DIR/$path" ]]; then
            STALE+=("$rel")
        fi
    # --no-renames принципиально. По умолчанию git засчитывает переезд файла как
    # R, и старый путь в список удалённых не попадает: спасает только relink в
    # install.sh — и ровно до тех пор, пока файл переезжает в ВКЛЮЧЁННЫЙ модуль.
    # Переедь он в модуль, которого на этой машине нет, install.sh его не
    # разложит, а старый симлинк остался бы висеть — тот самый мусор, ради
    # которого всё это и написано. С --no-renames переезд виден как D+A: старый
    # путь снимаем здесь, новый (если модуль включён) кладёт install.sh.
    done < <(git diff --name-only --no-renames --diff-filter=D "$OLD_HEAD..$NEW_HEAD" -- modules/)
}

# Пустые каталоги после снятия. `|| true`-логика через if: непустой каталог —
# норма, а не сбой, но под set -e падение последней команды в теле while
# уронило бы скрипт (та же ловушка, что в uninstall.sh и install.sh).
cleanup_dirs() {
    local rel dir acc comp d
    local -A dirs=()
    local -a parts

    for rel in "${STALE[@]}"; do
        dir="${rel%/*}"
        [[ "$dir" == "$rel" ]] && continue
        acc="$TARGET_DIR"
        IFS=/ read -ra parts <<< "$dir"
        for comp in "${parts[@]}"; do
            acc="$acc/$comp"
            dirs["$acc"]=1
        done
    done

    [[ ${#dirs[@]} -gt 0 ]] || return 0

    # От глубоких к мелким: иначе родитель ещё не пуст в момент проверки.
    while IFS= read -r d; do
        [[ -d "$d" ]] || continue
        if ((DRY_RUN)); then
            if [[ -z "$(ls -A "$d")" ]]; then
                echo "    rmdir $(short "$d")"
            fi
        elif rmdir "$d" 2>/dev/null; then
            echo "    rmdir $(short "$d")"
        fi
    done < <(printf '%s\n' "${!dirs[@]}" | awk '{print gsub(/\//,"/"), $0}' | sort -rn | cut -d' ' -f2-)
}

collect_stale

if [[ ${#STALE[@]} -gt 0 ]]; then
    echo "  устарело (файла в репе больше нет):"
    for rel in "${STALE[@]}"; do
        if ((DRY_RUN)); then
            echo "    rm ~/$rel"
        else
            rm -- "$TARGET_DIR/$rel"
            echo "    rm ~/$rel"
        fi
    done
    cleanup_dirs
    echo
fi

# ── Раскладка ────────────────────────────────────────────────────────────────
#
# Дальше обычная установка: она разложит новое, перелинкует переехавшее и
# перезапустит установщики тулов. Своей логики тут нет намеренно — дублировать
# install.sh значит однажды получить две разные раскладки.

exec "$DOTFILES_DIR/install.sh" ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"}
