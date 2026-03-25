autoload -U compinit; compinit

if [ -f "$HOME/.zshrc.local" ]; then source "$HOME/.zshrc.local"; fi

export STARSHIP_CONFIG="$HOME/.starship.config.toml"
STARSHIP="$HOME/.starship.darwin"

eval "$($STARSHIP init zsh)"

source "$HOME/.zinit.sh"
source "$HOME/.zinit.plugins.sh"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

. "$HOME/.local/bin/env"

# The next line updates PATH for UI Infra Ibazel CLI.
if [ -f '/Users/tihonove/.ui_infra/path.zsh.inc' ]; then source '/Users/tihonove/.ui_infra/path.zsh.inc'; fi

gfh() {
  # Проверяем, передали ли имя ветки
  if [ -z "$1" ]; then
    echo "❌ Ошибка: Укажи имя ветки."
    echo "💡 Использование: gfh users/balepas/INFRAUITEAM-1551"
    return 1
  fi

  local branch="$1"

  echo "🔄 Скачиваем отфильтрованную ветку..."
  # Пытаемся сделать fetch
  if git fetch origin "$branch"; then
    echo "🔀 Создаем локальную ветку и переключаемся..."
    git checkout -b "$branch" FETCH_HEAD
    
    # Жестко прописываем upstream в локальный конфиг гита
    git config branch."$branch".remote origin
    git config branch."$branch".merge "refs/heads/$branch"
    
    echo "✅ Готово! Ветка '$branch' привязана к origin."
    echo "Теперь 'git pull' и 'git push' будут работать без дополнительных флагов."
  else
    echo "❌ Ошибка: Не удалось скачать ветку '$branch'. Проверь имя."
    return 1
  fi
}

alias lyazi="yazi --client-id 54321"