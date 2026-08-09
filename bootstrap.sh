#!/bin/bash

# Точка входа на свежей машине. Ставит dotfiles с нуля, обновляет уже
# установленные и переводит на модульную схему те, где лежит старая версия.
#
# Запуск одной строкой:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tihonove/dotfiles/main/bootstrap.sh)"
#
# Три сценария, и скрипт сам решает, какой из них перед ним:
#
#   нет ~/.dotfiles          -> клон и установка
#   старая схема (без modules/) -> МИГРАЦИЯ (см. ниже) и установка
#   модульная схема          -> обычное обновление, то есть update.sh
#
# Отдельно про миграцию. Старая схема раскладывала симлинки иначе, в том числе
# на каталоги целиком, и простой сменой дерева не берётся: после переключения
# симлинки в ~ повисают битыми, а install.sh их не тронет — это не его пути.
# Ровно эту работу пришлось делать руками на трёх машинах, прежде чем она
# оказалась здесь.
#
# Чего скрипт НЕ делает намеренно: не ставит пакеты, не трогает /etc и не просит
# sudo. Всё, что он меняет, лежит в ~ и снимается через uninstall.sh.

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
# Переопределяется для тестов: прогонять миграцию на живой репе — плохая идея.
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/tihonove/dotfiles.git}"
BRANCH="${DOTFILES_BRANCH:-main}"
BACKUP_DIR="$HOME/dotfiles-old"

short() { echo "~${1#"$HOME"}"; }
say()   { echo "$*"; }
die()   { echo "❌ $*" >&2; exit 1; }

command -v git  >/dev/null || die "нужен git, а его нет. Поставь и запусти снова."
command -v curl >/dev/null || die "нужен curl, а его нет."

# ── Миграция со старой схемы ─────────────────────────────────────────────────

# Данные, которые ЖИВУТ внутри репы. На рабочей машине таким оказался ~/.claude:
# симлинк вёл в ~/.dotfiles/.claude, а там 173 МБ истории и проектов. Каталог
# был в .gitignore, то есть `git clean -ffdx` снёс бы его молча.
#
# Отличаем данные от содержимого репы по git: цель симлинка ОТСЛЕЖИВАЕТСЯ —
# значит это конфиг из репы, симлинк просто снимаем. НЕ отслеживается — значит
# чужие данные, и их надо вынести наружу, на место симлинка.
rescue_untracked_targets() {
    local link target rescued=0

    while IFS= read -r link; do
        target="$(readlink -- "$link")"
        [[ "$target" == "$DOTFILES_DIR"/* ]] || continue
        [[ -e "$target" ]] || continue

        # Отслеживаемое git'ом — содержимое репы, спасать нечего.
        if git -C "$DOTFILES_DIR" ls-files --error-unmatch -- "$target" >/dev/null 2>&1; then
            continue
        fi
        # Каталог с чем-то внутри — считаем данными.
        [[ -d "$target" ]] || continue

        say "  спасаю данные: $(short "$link") — внутри репы, гитом не отслеживается"
        say "    $(du -sh "$target" 2>/dev/null | cut -f1) -> $(short "$link")"
        rm -- "$link"
        mv -- "$target" "$link"
        rescued=$((rescued + 1))
    done < <(find "$HOME" -maxdepth 4 -type l 2>/dev/null)

    ((rescued)) || say "  данных внутри репы не нашлось"
}

# Локальные слои прежней схемы. Их содержимое машинно-специфично (на рабочей
# машине это корпоративное окружение и рабочая личность в git), потерять его
# нельзя. В новой схеме то же самое живёт прямо в ~/.bashrc вне блоков и в
# ~/.gitconfig, поэтому просто переносим как есть — разбирать, что там ещё
# актуально, человек может и потом.
migrate_local_layers() {
    if [[ -f "$HOME/.bashrc.local" ]]; then
        # ~/.bashrc сейчас симлинк в старую репу — на его место кладём обычный
        # файл с локальным содержимым. Блоки допишет install.sh.
        [[ -L "$HOME/.bashrc" ]] && rm -- "$HOME/.bashrc"
        {
            echo "# ~/.bashrc — машинно-локальная часть."
            echo "#"
            echo "# Перенесено bootstrap.sh из ~/.bashrc.local прежней схемы. Управляемую"
            echo "# часть дописывает install.sh маркированными блоками; всё, что вне них,"
            echo "# считается локальным и в репу не уезжает."
            echo
            cat "$HOME/.bashrc.local"
        } >> "$HOME/.bashrc"
        mv -- "$HOME/.bashrc.local" "$BACKUP_DIR/.bashrc.local.was-in-home"
        say "  ~/.bashrc.local -> перенесён в ~/.bashrc (вне блоков)"
    fi

    if [[ -f "$HOME/.gitconfig.local" ]]; then
        [[ -L "$HOME/.gitconfig" ]] && rm -- "$HOME/.gitconfig"
        {
            echo "# Локальный слой git. Управляемая часть — в ~/.config/git/config,"
            echo "# git читает её раньше, поэтому здесь перекрывается что угодно."
            echo "#"
            echo "# Перенесено bootstrap.sh из ~/.gitconfig.local прежней схемы."
            echo
            cat "$HOME/.gitconfig.local"
        } >> "$HOME/.gitconfig"
        mv -- "$HOME/.gitconfig.local" "$BACKUP_DIR/.gitconfig.local.was-in-home"
        say "  ~/.gitconfig.local -> перенесён в ~/.gitconfig"
    fi
}

# Снимаем ВСЁ, что указывает в репу. Новую раскладку положит install.sh, а то,
# что в новой схеме не предусмотрено, иначе осталось бы висеть битым.
unlink_old_layout() {
    local link n=0
    while IFS= read -r link; do
        [[ "$(readlink -- "$link")" == "$DOTFILES_DIR"/* ]] || continue
        rm -- "$link"
        n=$((n + 1))
    done < <(find "$HOME" -maxdepth 4 -type l 2>/dev/null)
    say "  снято симлинков старой схемы: $n"

    # Каталоги, опустевшие после снятия. rmdir сам откажется, если внутри чужое.
    #
    # mindepth 1 — чтобы в список не попал сам ~/.config: на машине, где кроме
    # наших симлинков в нём ничего не лежало, он оказывался пуст и удалялся
    # целиком. Формально безвредно (пустой же), но каталог с таким именем сносить
    # не наше дело — его тут же начнёт создавать заново любая программа.
    local d
    while IFS= read -r d; do
        [[ -d "$d" ]] || continue
        rmdir "$d" 2>/dev/null && say "  rmdir $(short "$d")"
    done < <(find "$HOME/.config" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
    true
}

migrate_from_old_scheme() {
    say "🔄 Обнаружена старая схема — перевожу на модульную."
    say ""

    # Снимок: ВЕТКА в репе плюс копия дерева рядом. Дальше по кускам переносится
    # руками, README новой репы на этот каталог и рассчитан.
    #
    # Именно ветка, а не тег, и это выясненное на живой машине. Наш же
    # управляемый git-конфиг ставит fetch.pruneTags = true, поэтому первый же
    # fetch — а он делается пятью строками ниже — сносит локальный тег, которого
    # нет на remote. Страховка испарялась бы прямо внутри этого скрипта, а
    # незапушенные коммиты оставались бы только в reflog, который протухает.
    # Локальные ветки fetch не трогает.
    git -C "$DOTFILES_DIR" branch -f old-scheme HEAD >/dev/null 2>&1 || true
    rm -rf "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    git -C "$DOTFILES_DIR" archive HEAD 2>/dev/null | tar -x -C "$BACKUP_DIR" || true
    say "  снимок старой версии: $(short "$BACKUP_DIR") ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1))"
    say "  ветка old-scheme оставлена в репе — незапушенные коммиты не потеряются"

    rescue_untracked_targets
    migrate_local_layers
    unlink_old_layout

    # reset, а не pull: расхождение между схемами слишком велико, а на машине
    # могли остаться и локальные коммиты (тег old-scheme их держит).
    git -C "$DOTFILES_DIR" fetch --quiet origin
    git -C "$DOTFILES_DIR" checkout --quiet -B "$BRANCH" "origin/$BRANCH"
    git -C "$DOTFILES_DIR" reset --hard --quiet "origin/$BRANCH"
    git -C "$DOTFILES_DIR" clean -ffdxq
    say "  репа переведена на origin/$BRANCH"
    say ""
}

# ── Сценарии ─────────────────────────────────────────────────────────────────

is_modular() { [[ -d "$DOTFILES_DIR/modules" ]]; }

if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    if [[ -e "$DOTFILES_DIR" ]]; then
        die "$(short "$DOTFILES_DIR") существует, но это не git-репозиторий. Разберись руками."
    fi
    say "🚀 Клонирую dotfiles в $(short "$DOTFILES_DIR")..."
    git clone --quiet "$DOTFILES_REPO" "$DOTFILES_DIR"
    say ""
elif is_modular; then
    # Уже новая схема — обновление это отдельный скрипт, дублировать его нечего.
    say "✅ Модульная схема уже стоит — обновляю."
    say ""
    exec "$DOTFILES_DIR/update.sh" "$@"
else
    migrate_from_old_scheme
fi

is_modular || die "в $(short "$DOTFILES_DIR") нет каталога modules/ — это не та версия репы."

say "[*] Запускаю install.sh..."
say ""
chmod +x "$DOTFILES_DIR/install.sh"
"$DOTFILES_DIR/install.sh" "$@"

say ""
say "🎉 Готово. Открой новый терминал — текущая сессия старый конфиг не перечитает."
say "   Модули этой машины: ./install.sh list  |  добавить: ./install.sh add <модуль>"
if [[ -d "$BACKUP_DIR" ]]; then
    say "   Старая версия лежит в $(short "$BACKUP_DIR") — переносить из неё по кускам."
fi
