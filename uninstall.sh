#!/bin/bash

# Снятие dotfiles: убирает из домашнего каталога то, что положил install.sh.
#
# Зачем отдельный скрипт. Раскладка ставится одной командой, а снималась руками
# — и на каждой машине заново: найти симлинки, не спутать их с чужими, вспомнить
# про блоки в ~/.bashrc. При переезде со старой схемы на модульную это делалось
# вручную и заняло больше времени, чем сама установка.
#
# Главное правило: удаляется ТОЛЬКО то, про что точно известно, что это наше.
# Для файла это значит «симлинк, указывающий ровно на наш файл в репе». Не
# симлинк — не трогаем (значит, это чужой файл, лёгший на то же место). Симлинк,
# указывающий не к нам, — тоже не трогаем: чужая раскладка не наше дело.
# Поэтому снятие безопаснее установки: та хотя бы уносила файлы в .backup, а
# эта не удаляет ничего, чего не создавала.
#
# По умолчанию берутся ВСЕ модули репы, а не только включённые в профиле. Так и
# надо: `install.sh remove <мод>` симлинки не снимает (и честно об этом пишет),
# поэтому на машине запросто лежит раскладка модуля, которого в профиле уже нет.
# Снять «всё, что мы когда-либо положили» — ровно тот случай, ради которого
# скрипт и написан. Ограничить профилем — --profile.
#
# Что НЕ трогается никогда, и почему:
#
#   ~/.gitconfig      локальный слой. Пустым его создал install.sh, но дописать
#                     туда могли и мы, и devsy, и `git config --global`.
#   ~/.ssh/config.d/  инвентарь. Он в репу и не уезжал, снимать его вместе с
#                     раскладкой — потерять то, чего в гите нет.
#   ~/.config/dotfiles/profile
#                     машинный выбор модулей. Переставить dotfiles и получить
#                     обратно свой набор — приятно. Убрать вместе со всем: --purge.
#   ~/.local/bin/*    starship, fzf, devsy, vexx: их ставили modules/*/update,
#                     это обычные бинарники, а не раскладка. Показываются в конце
#                     списком — снимать их или нет, решает человек.
#
# Использование:
#   ./uninstall.sh              снять раскладку всех модулей репы
#   ./uninstall.sh --dry-run    показать, что будет снято, ничего не менять
#   ./uninstall.sh --profile    только модули, включённые в профиле
#   ./uninstall.sh --purge      снять и профиль тоже (и пустой ~/.gitconfig)

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$DOTFILES_DIR/modules"
TARGET_DIR="$HOME"

PROFILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/profile"

BASHRC="$HOME/.bashrc"
GITCONFIG="$HOME/.gitconfig"
BEGIN_MARK='# >>> dotfiles >>>'
END_MARK='# <<< dotfiles <<<'
LATE_BEGIN_MARK='# >>> dotfiles prompt >>>'
LATE_END_MARK='# <<< dotfiles prompt <<<'

DRY_RUN=0
ONLY_PROFILE=0
PURGE=0

short() { echo "~${1#"$HOME"}"; }

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --profile) ONLY_PROFILE=1 ;;
        --purge)   PURGE=1 ;;
        *) echo "usage: ${0##*/} [--dry-run] [--profile] [--purge]" >&2; exit 2 ;;
    esac
done

# ── Модули ───────────────────────────────────────────────────────────────────

declare -a MODULES=()

read_profile() {
    local line
    local -A seen=()

    MODULES=(core)
    seen[core]=1

    [[ -f "$PROFILE" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] || continue
        [[ -n "${seen[$line]-}" ]] && continue
        seen[$line]=1
        MODULES+=("$line")
    done < "$PROFILE"
}

read_all_modules() {
    local dir
    MODULES=()
    for dir in "$MODULES_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        MODULES+=("$(basename "$dir")")
    done
}

# ── План ─────────────────────────────────────────────────────────────────────
#
# Три корзины. Разделение не косметическое: удаляется только первая, а две
# другие показываются, чтобы человек видел, что осталось и почему.

declare -a TO_REMOVE=()     # наши симлинки — снимаем
declare -a FOREIGN=()       # на нашем месте лежит чужое — не трогаем
declare -a ALREADY=()       # ничего нет — уже снято

build_plan() {
    local m src f rel target link

    for m in "${MODULES[@]}"; do
        src="$MODULES_DIR/$m/home"
        [[ -d "$src" ]] || continue

        while IFS= read -r -d '' f; do
            rel="${f#"$src"/}"
            target="$TARGET_DIR/$rel"

            if [[ -L "$target" ]]; then
                link="$(readlink -- "$target")"
                if [[ "$link" == "$f" ]]; then
                    TO_REMOVE+=("$rel")
                else
                    # Симлинк есть, но ведёт не к нам. Частый случай — файл
                    # переехал между модулями и указывает на другой модуль этой
                    # же репы; тогда его снимет итерация того модуля.
                    [[ "$link" == "$DOTFILES_DIR"/* ]] || FOREIGN+=("$rel — симлинк на $link")
                fi
            elif [[ -e "$target" ]]; then
                FOREIGN+=("$rel — обычный файл, не наш симлинк")
            else
                ALREADY+=("$rel")
            fi
        done < <(find "$src" -type f -print0 | sort -z)
    done
}

# ── ~/.bashrc ────────────────────────────────────────────────────────────────

# Блоки вырезаются вместе с маркерами; всё, что между блоками и вокруг них,
# остаётся как было — это машинно-локальное, и оно переживало установку, значит
# обязано пережить и снятие. Пустая строка, которую install.sh ставил перед
# блоком, схлопывается, чтобы файл не копил их от цикла к циклу.
strip_bashrc_blocks() {
    [[ -f "$BASHRC" ]] || { echo "  ~/.bashrc: нет файла"; return 0; }

    # `|| true`: ненайденный маркер — обычный ответ «блока нет», а не сбой.
    # Без него set -e вышибал бы скрипт на первой же машине без наших блоков.
    local found=0
    grep -qxF "$BEGIN_MARK" "$BASHRC" && found=1 || true
    grep -qxF "$LATE_BEGIN_MARK" "$BASHRC" && found=1 || true

    if ((!found)); then
        echo "  ~/.bashrc: наших блоков нет"
        return 0
    fi

    if ((DRY_RUN)); then
        echo "  ~/.bashrc: вырезал бы блоки (остальное осталось бы нетронутым)"
        return 0
    fi

    local tmp="$BASHRC.dotfiles-tmp.$$"
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" \
        -v lb="$LATE_BEGIN_MARK" -v le="$LATE_END_MARK" '
        $0 == b || $0 == lb { inblock = 1; skipped = 1; next }
        $0 == e || $0 == le { inblock = 0; next }
        inblock { next }
        # схлопываем пустые строки, оставшиеся от вырезанного блока
        skipped && NF == 0 { next }
        { skipped = 0; print }
    ' "$BASHRC" > "$tmp"

    cp "$BASHRC" "$BASHRC.backup.$(date +%Y%m%d_%H%M%S)"
    mv "$tmp" "$BASHRC"
    echo "  ~/.bashrc: блоки вырезаны (бэкап рядом)"
}

# ── Пустые каталоги ──────────────────────────────────────────────────────────
#
# install.sh создавал промежуточные каталоги обычными, и после снятия симлинков
# часть из них остаётся пустой. Удаляем строго пустые и строго те, что были на
# пути наших файлов: rmdir сам откажется, если внутри лежит чужое.
cleanup_dirs() {
    local rel dir acc
    local -A dirs=()

    for rel in "${TO_REMOVE[@]}"; do
        dir="${rel%/*}"
        [[ "$dir" == "$rel" ]] && continue
        acc="$TARGET_DIR"
        local -a parts
        IFS=/ read -ra parts <<< "$dir"
        for comp in "${parts[@]}"; do
            acc="$acc/$comp"
            dirs["$acc"]=1
        done
    done

    # От глубоких к мелким: иначе родитель ещё не пуст в момент проверки.
    # Про `|| true` в конце тела: непустой каталог — это норма, а не сбой, но
    # под set -e падение последней команды в теле while роняет весь скрипт.
    # Ровно та же ловушка, из-за которой в install.sh нельзя ((n++)).
    local d
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

# ── Выполнение ───────────────────────────────────────────────────────────────

if ((ONLY_PROFILE)); then
    read_profile
    echo "Снятие dotfiles: модули профиля — ${MODULES[*]}"
else
    read_all_modules
    echo "Снятие dotfiles: все модули репы — ${MODULES[*]}"
fi
((DRY_RUN)) && echo "(--dry-run: ничего не меняется)"
echo

build_plan

if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    echo "  наших симлинков в $(short "$TARGET_DIR") не найдено"
else
    for rel in "${TO_REMOVE[@]}"; do
        if ((DRY_RUN)); then
            echo "    rm ~/$rel"
        else
            rm -- "$TARGET_DIR/$rel"
            echo "    rm ~/$rel"
        fi
    done
    echo
    cleanup_dirs
fi

echo
strip_bashrc_blocks

if ((PURGE)); then
    if [[ -f "$PROFILE" ]]; then
        ((DRY_RUN)) && echo "  профиль: удалил бы $(short "$PROFILE")" || {
            rm "$PROFILE"; echo "  профиль: $(short "$PROFILE") удалён"; }
    fi
    # Только если пуст по содержанию: непустой — это уже чей-то локальный слой.
    if [[ -f "$GITCONFIG" ]] && ! grep -qvE '^\s*#|^\s*$' "$GITCONFIG"; then
        ((DRY_RUN)) && echo "  ~/.gitconfig: удалил бы (пустой локальный слой)" || {
            rm "$GITCONFIG"; echo "  ~/.gitconfig: удалён (был пуст)"; }
    fi
fi

echo
echo "  снято: ${#TO_REMOVE[@]}, уже не было: ${#ALREADY[@]}, чужое (не тронуто): ${#FOREIGN[@]}"

if [[ ${#FOREIGN[@]} -gt 0 ]]; then
    echo
    echo "  На наших путях лежит не наше — оставлено как есть:"
    printf '    • %s\n' "${FOREIGN[@]}"
fi

# Бинарники ставил не install.sh-раскладчик, а modules/*/update. Удалить их
# автоматически нельзя: тот же ~/.local/bin/fzf мог приехать и не от нас.
declare -a TOOLS=()
for t in starship fzf devsy vexx; do
    if [[ -x "$HOME/.local/bin/$t" ]]; then TOOLS+=("$t"); fi
done
if [[ -d "$HOME/.local/share/blesh" ]]; then TOOLS+=("blesh (~/.local/share/blesh)"); fi

if [[ ${#TOOLS[@]} -gt 0 ]]; then
    echo
    echo "  Оставлено намеренно — это тулы, а не раскладка:"
    printf '    • %s\n' "${TOOLS[@]}"
    echo "    Не нужны — убрать руками из ~/.local/bin и ~/.local/share."
fi

echo
if ((DRY_RUN)); then
    echo "✅ План проверен, изменений не вносилось"
else
    echo "✅ Готово. Саму репу ($(short "$DOTFILES_DIR")) можно удалять."
fi
