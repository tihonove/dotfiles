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

alias lyazi="yazi --client-id 54321"