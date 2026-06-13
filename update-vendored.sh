#!/bin/bash

# Обновление вендоренных зависимостей до последних релизов:
#   - catppuccin/tmux — копия кладётся в .tmux_plugins/catppuccin (закоммитить вручную)
#   - fzf — готовый бинарник скачивается в ~/.local/bin
#   - vexx — nightly-бинарник скачивается в .dotfiles.scripts (в git не хранится, см. .gitignore)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

update_catppuccin() {
    echo "Обновление catppuccin/tmux..."
    local repo="https://github.com/catppuccin/tmux.git"
    local target="$DOTFILES_DIR/.tmux_plugins/catppuccin"

    local tag
    tag=$(git ls-remote --tags --sort=-v:refname "$repo" \
        | grep -oP 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -1 | sed 's|refs/tags/||')
    if [[ -z "$tag" ]]; then
        echo "❌ Не удалось определить последний тег catppuccin/tmux" >&2
        return 1
    fi
    echo "  Последний релиз: $tag"

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" "$repo" "$tmp/catppuccin"

    mkdir -p "$target"
    rsync -a --delete \
        --exclude '.git' --exclude '.github' --exclude 'assets' \
        "$tmp/catppuccin/" "$target/"
    echo "$tag" > "$target/VERSION"

    echo "✅ catppuccin/tmux обновлён до $tag (не забудь закоммитить .tmux_plugins/catppuccin)"
}

update_fzf() {
    echo "Обновление fzf..."

    local arch
    case $(uname -m) in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7" ;;
        *)
            echo "❌ Неизвестная архитектура: $(uname -m)" >&2
            return 1
            ;;
    esac

    local version
    version=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest \
        | grep -oP '"tag_name":\s*"v\K[0-9.]+')
    if [[ -z "$version" ]]; then
        echo "❌ Не удалось определить последнюю версию fzf" >&2
        return 1
    fi
    echo "  Последний релиз: v$version"

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    curl -fsSL -o "$tmp/fzf.tar.gz" \
        "https://github.com/junegunn/fzf/releases/download/v${version}/fzf-${version}-linux_${arch}.tar.gz"
    tar -xzf "$tmp/fzf.tar.gz" -C "$tmp"

    mkdir -p "$HOME/.local/bin"
    install -m 755 "$tmp/fzf" "$HOME/.local/bin/fzf"

    echo "✅ fzf обновлён: $("$HOME/.local/bin/fzf" --version)"
}

update_vexx() {
    echo "Обновление vexx..."

    local asset
    case $(uname -m) in
        x86_64) asset="vexx-linux-x64" ;;
        *)
            echo "⚠️  nightly-бинарник vexx есть только под x86_64, пропускаю (архитектура: $(uname -m))" >&2
            return 0
            ;;
    esac

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN

    curl -fsSL -o "$tmp/vexx" \
        "https://github.com/tihonove/vexx/releases/download/nightly/$asset"

    install -m 755 "$tmp/vexx" "$DOTFILES_DIR/.dotfiles.scripts/vexx"

    echo "✅ vexx (nightly) обновлён: $DOTFILES_DIR/.dotfiles.scripts/vexx"
}

update_catppuccin
update_fzf
update_vexx

echo ""
echo "✅ Все вендоренные зависимости обновлены!"
