#!/bin/bash
# uncommit — развернуть коммиты ветки обратно в незакоммиченные правки рабочей
# копии, чтобы смотреть их как обычный дифф и править прямо в коде.
#
# Зачем: агент работает в своём worktree и коммитит по ходу, а ревью удобнее
# делать по рабочей копии, а не по коммитам. Механика — mixed reset на базу:
# ветка откатывается, индекс сбрасывается, файлы остаются как есть.
#
#   uncommit [--all | --last [N]] [--here | --main] [--base <ref>] [-n] [<ветка>]
#   uncommit --restack [<ref>]
#
# Объём:
#   --all        все коммиты задачи: до merge-base с базовой веткой (по умолчанию)
#   --last [N]   только последние N коммитов (N по умолчанию 1)
#   --base REF   базовая ветка для --all; иначе origin/HEAD, origin/trunk,
#                origin/main, origin/master — что найдётся первым
#
# Где:
#   --here       на месте, в worktree ветки (по умолчанию)
#   --main       перенести в основной worktree: ветка переезжает туда, worktree
#                агента остаётся отвязанным (detached) на прежнем tip
#
# Прежний tip ветки сохраняется в refs/uncommit/<ветка>, отсюда обратный ход:
#   --restack    вернуть ветку на сохранённый tip, НЕ трогая файлы: в рабочей
#                копии остаётся только то, что поправлено на ревью — коммить
#                поверх. Ссылку можно задать явно (например origin/<ветка>).
#
# <ветка> — если запускать не из её worktree. Ветка без worktree допустима
# только с --main: тогда она просто выезжает в основной worktree.

set -euo pipefail

die()  { echo "uncommit: $*" >&2; exit 1; }
note() { echo "  $*"; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

SCOPE=all
N=1
WHERE=here
BASE_REF=""
DRY=0
RESTACK=0
RESTACK_REF=""
SRC=""

while (($#)); do
    case "$1" in
        --all)   SCOPE=all ;;
        --last)  SCOPE=last
                 if [[ "${2-}" =~ ^[0-9]+$ ]]; then N=$2; shift; fi ;;
        --here)  WHERE=here ;;
        --main)  WHERE=main ;;
        --base)  [[ -n "${2-}" ]] || die "--base требует ref"; BASE_REF=$2; shift ;;
        -n|--dry-run) DRY=1 ;;
        --restack) RESTACK=1
                 if [[ -n "${2-}" && "${2:0:1}" != - ]]; then RESTACK_REF=$2; shift; fi ;;
        -h|--help) usage; exit 0 ;;
        -*)      die "неизвестная опция: $1 (см. --help)" ;;
        *)       [[ -z "$SRC" ]] || die "лишний аргумент: $1"; SRC=$1 ;;
    esac
    shift
done

g() { git -C "$1" "${@:2}"; }

# Путь worktree, в котором выписана ветка; пусто — ни в одном.
worktree_of_branch() {
    g "$1" worktree list --porcelain | awk -v b="refs/heads/$2" '
        /^worktree /{wt=substr($0,10)} /^branch /{if ($2==b){print wt; exit}}'
}

main_worktree() { g "$1" worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}'; }

dirty() { [[ -n "$(g "$1" status --porcelain --untracked-files=no)" ]]; }

detect_base() {
    local r
    for r in origin/HEAD origin/trunk origin/main origin/master; do
        g "$1" rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1 && { echo "$r"; return; }
    done
    die "не нашёл базовую ветку (origin/HEAD, trunk, main, master) — укажи --base"
}

# ── restack ──────────────────────────────────────────────────────────────────

if ((RESTACK)); then
    dir=$(git rev-parse --show-toplevel 2>/dev/null) || die "не в git-репозитории"
    branch=$(g "$dir" symbolic-ref -q --short HEAD) || die "HEAD отвязан — на какую ветку возвращать?"
    ref=$RESTACK_REF
    saved="refs/uncommit/$branch"
    if [[ -z "$ref" ]]; then
        if g "$dir" rev-parse -q --verify "$saved^{commit}" >/dev/null; then
            ref=$saved
        elif g "$dir" rev-parse -q --verify "origin/$branch^{commit}" >/dev/null; then
            ref="origin/$branch"
            note "сохранённого tip нет, беру origin/$branch"
        else
            die "нет ни $saved, ни origin/$branch — укажи ref явно"
        fi
    fi
    g "$dir" merge-base --is-ancestor HEAD "$ref" \
        || die "HEAD не предок $ref — ветка уехала после uncommit, разбирайся руками"
    echo "restack $branch: HEAD $(g "$dir" rev-parse --short HEAD) -> $ref $(g "$dir" rev-parse --short "$ref")"
    if ((DRY)); then note "(dry-run) git reset --mixed $ref"; exit 0; fi
    g "$dir" reset -q --mixed "$ref"
    [[ "$ref" == "$saved" ]] && g "$dir" update-ref -d "$saved"
    echo
    echo "в рабочей копии остались только правки ревью:"
    g "$dir" status --short | sed 's/^/  /'
    echo
    note "дальше: git commit -a"
    exit 0
fi

# ── uncommit ─────────────────────────────────────────────────────────────────

# Откуда берём коммиты.
if [[ -n "$SRC" && -d "$SRC" ]]; then
    src_dir=$(g "$SRC" rev-parse --show-toplevel) || die "$SRC — не git-репозиторий"
    branch=$(g "$src_dir" symbolic-ref -q --short HEAD) || die "в $SRC HEAD отвязан"
elif [[ -n "$SRC" ]]; then
    cwd=$(git rev-parse --show-toplevel 2>/dev/null) || die "не в git-репозитории"
    g "$cwd" rev-parse -q --verify "refs/heads/$SRC" >/dev/null || die "нет ветки $SRC"
    branch=$SRC
    src_dir=$(worktree_of_branch "$cwd" "$branch")
    if [[ -z "$src_dir" ]]; then
        [[ "$WHERE" == main ]] || die "ветка $branch не выписана ни в одном worktree — только с --main"
        src_dir=$cwd    # worktree нет: ветку просто выпишем в основной
    fi
else
    src_dir=$(git rev-parse --show-toplevel 2>/dev/null) || die "не в git-репозитории"
    branch=$(g "$src_dir" symbolic-ref -q --short HEAD) || die "HEAD отвязан — укажи ветку"
fi

main_dir=$(main_worktree "$src_dir")
branch_wt=$(worktree_of_branch "$src_dir" "$branch")
[[ "$WHERE" == main && "$branch_wt" == "$main_dir" ]] && WHERE=here
[[ "$WHERE" == here && -z "$branch_wt" ]] && die "ветка $branch нигде не выписана"
[[ "$WHERE" == here ]] && src_dir=$branch_wt

tip=$(g "$src_dir" rev-parse "refs/heads/$branch")
case "$SCOPE" in
    last) base=$(g "$src_dir" rev-parse -q --verify "$tip~$N") || die "в $branch нет $N коммитов" ;;
    all)  [[ -n "$BASE_REF" ]] || BASE_REF=$(detect_base "$src_dir")
          base=$(g "$src_dir" merge-base "$tip" "$BASE_REF") || die "нет merge-base с $BASE_REF" ;;
esac
[[ "$base" != "$tip" ]] && [[ -n "$(g "$src_dir" rev-list -n1 "$base..$tip")" ]] \
    || die "между $(g "$src_dir" rev-parse --short "$base") и tip ветки $branch коммитов нет"

[[ "$SCOPE" == last ]] && what="последние $N" || what="вся задача, от $BASE_REF"
echo "uncommit $branch ($what):"
g "$src_dir" log --oneline "$base..$tip" | sed 's/^/  /'
echo

if [[ "$WHERE" == main ]]; then
    target_dir=$main_dir
    dirty "$main_dir" && die "основной worktree грязный ($main_dir) — закоммить или stash"
    [[ -n "$branch_wt" ]] && dirty "$branch_wt" \
        && die "в worktree ветки есть незакоммиченное ($branch_wt) — оно не переедет; закоммить или stash"
    note "основной worktree: $main_dir ($(g "$main_dir" symbolic-ref -q --short HEAD || echo detached))"
    [[ -n "$branch_wt" ]] && note "worktree ветки:    $branch_wt — останется отвязанным на $(g "$src_dir" rev-parse --short "$tip")"
else
    target_dir=$src_dir
    dirty "$src_dir" && note "в рабочей копии уже есть незакоммиченное — оно смешается с развёрнутым"
fi
note "tip сохраняется в refs/uncommit/$branch = $(g "$src_dir" rev-parse --short "$tip")"

if ((DRY)); then
    echo
    note "(dry-run) ничего не сделано"
    exit 0
fi

g "$src_dir" update-ref "refs/uncommit/$branch" "$tip"
if [[ "$WHERE" == main ]]; then
    # Сначала выписать ветку в основной (пока её держит другой worktree —
    # через --ignore-other-worktrees), и только потом отвязать worktree агента:
    # если checkout откажет, ничего ещё не изменено.
    g "$main_dir" checkout -q --ignore-other-worktrees "$branch"
    [[ -n "$branch_wt" ]] && g "$branch_wt" checkout -q --detach
fi
g "$target_dir" reset -q --mixed "$base"

echo
echo "готово: $target_dir на $branch @ $(g "$target_dir" rev-parse --short HEAD), в рабочей копии:"
g "$target_dir" status --short | sed 's/^/  /'
echo
note "вернуть коммиты (правки ревью останутся поверх): uncommit --restack"
