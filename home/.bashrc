# ~/.bashrc — интерактивный bash.
# Собирается с нуля: в него въезжает только то, что осознанно перенесено
# из ~/dotfiles-old. Пусто по умолчанию, а не «стоковый плюс правки».

# Неинтерактивный шелл — ничего не делаем.
case $- in
    *i*) ;;
      *) return;;
esac

# ble.sh — автодополнение, подсветка синтаксиса, редактор строки.
# Ставится в ~/.local/share/blesh через update-tools.sh, конфиг —
# ~/.config/blesh/init.sh.
#
# Грузить надо в начале .bashrc, а attach делать в самом конце (см. низ файла):
# с --attach=none ble.sh не трогает PROMPT_COMMAND, и starship успевает
# поставить свой промпт первым.
#
# Гард [[ -f ]] по тому же принципу, что command -v у starship: недокачанный или
# отсутствующий ble.sh не должен ронять старт шелла.
[[ -f $HOME/.local/share/blesh/ble.sh ]] &&
    source -- "$HOME/.local/share/blesh/ble.sh" --attach=none

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

# Подцепить ble.sh — обязательно последней строкой, после starship.
# Условие само себе гард: если ble.sh не загрузился выше, BLE_VERSION пуст.
[[ ! ${BLE_VERSION-} ]] || ble-attach
