# ~/.bashrc — интерактивный bash.
# Собирается с нуля: в него въезжает только то, что осознанно перенесено
# из ~/dotfiles-old. Пусто по умолчанию, а не «стоковый плюс правки».

# Неинтерактивный шелл — ничего не делаем.
case $- in
    *i*) ;;
      *) return;;
esac

# ~/.local/bin — туда update-tools.sh ставит внешние тулзы (starship и пр.).
# ~/.profile добавляет этот путь только в login-шелле и только ПОСЛЕ того,
# как отработал ~/.bashrc, поэтому прописываем сами. Идемпотентно.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# История
HISTCONTROL=ignoreboth   # без дублей и команд, начинающихся с пробела
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend      # дописывать, а не перетирать при выходе

shopt -s checkwinsize    # обновлять LINES/COLUMNS после каждой команды

if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# Промпт. Конфиг — ~/.config/starship.toml (дефолтный путь starship).
# Гард через `command -v` обязателен: если бинарника нет или он битый,
# подстановка `$(...)` подвесит старт шелла навсегда, а не упадёт с ошибкой.
command -v starship >/dev/null && eval "$(starship init bash)"
