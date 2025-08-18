autoload -U compinit; compinit

if [ -f "$HOME/.zshrc.local" ]; then source "$HOME/.zshrc.local"; fi

export STARSHIP_CONFIG="$HOME/.starship.config.toml"
STARSHIP="$HOME/.starship.darwin"

eval "$($STARSHIP init zsh)"

source "$HOME/.zinit.sh"
source "$HOME/.zinit.plugins.sh"
