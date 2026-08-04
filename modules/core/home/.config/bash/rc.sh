# Управляемая часть конфига интерактивного bash.
# Собирается с нуля: сюда въезжает только то, что осознанно перенесено
# из ~/dotfiles-old. Пусто по умолчанию, а не «стоковый плюс правки».
#
# Сам ~/.bashrc под гитом НЕ лежит: это машинно-локальный файл, куда чужие
# инсталляторы дописывают своё (обычно PATH), а install.sh один раз добавляет
# маркированные блоки с source. Подробности — в README, раздел «Почему
# ~/.bashrc не симлинк».
#
# Блоков ДВА, и этот файл — ранний. Он идёт в начало ~/.bashrc: всё, что
# дописано ниже, выполняется после него. Для PATH это то, что нужно, — чужой
# путь ложится позже и побеждает. А вот промпт по той же причине проигрывал бы:
# чужой ~/.bashrc, задающий PS1 ниже (так делает базовый образ devcontainer),
# просто затирал бы starship. Поэтому промпт вынесен в prompt.sh, который
# подключается ПОСЛЕДНИМ блоком, в конце ~/.bashrc.
#
# Здесь, соответственно, всё, чему безразличен чужой хвост: PATH, история,
# автодополнение, загрузка ble.sh (но не attach).

# Неинтерактивный шелл — ничего не делаем.
case $- in
    *i*) ;;
      *) return;;
esac

# ble.sh — автодополнение, подсветка синтаксиса, редактор строки.
# Ставится в ~/.local/share/blesh через update-tools.sh, конфиг —
# ~/.config/blesh/init.sh.
#
# Грузить надо в начале, а attach делать в самом конце (см. низ файла):
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

# fzf. Ставится пакетом (см. README, раздел «Пакеты»), поэтому тут только
# настройка.
#
# --color=16 — то, из-за чего fzf следует теме: он рисует ANSI-цветами, а
# палитру 0..15 kitty перекрашивает на лету по theme-toggle. Дефолтная схема
# fzf прибита к конкретным 256-цветным значениям, подобранным под тёмный фон,
# и в светлой теме читается плохо.
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --color=16'

# Биндинги C-r / C-t / M-c при живом ble.sh подключает ОН — см.
# ~/.config/blesh/init.sh, там же почему. Здесь только запасной путь для
# случая, когда ble.sh не загрузился: свежая машина до update-tools.sh или
# битая закачка. Иначе fzf остался бы вообще без биндингов.
if [[ ! ${BLE_VERSION-} ]] && command -v fzf >/dev/null; then
    eval "$(fzf --bash)"
fi

# Промпт и ble-attach — не здесь, а в ~/.config/bash/prompt.sh: их обязано
# выполнять ПОСЛЕ всего чужого содержимого ~/.bashrc. См. шапку файла.
