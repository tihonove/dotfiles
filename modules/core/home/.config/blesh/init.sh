# ~/.config/blesh/init.sh — конфигурация ble.sh
# Приглушённая цветовая схема, близкая к zsh-syntax-highlighting
#
# В старых dotfiles файл лежал в ~/.blerc. ble.sh ищет rcfile в порядке
# ~/.blerc → ${XDG_CONFIG_HOME:-~/.config}/blesh/init.sh, так что этот путь
# подхватывается сам, без флагов. Сам ble.sh ставит update-tools.sh.
#
# Все face'ы секции задаются ОДНИМ вызовом ble-face в форме NAME=SPEC.
# Это не косметика: 68 поштучных `ble-face -s` стоили 200 мс на каждом старте
# интерактивного шелла — вдвое дороже самого ble.sh. Пакетная форма убирает эту
# цену полностью, таблица face'ов получается побайтово та же.
#
# ВНИМАНИЕ: NAME=SPEC — это один аргумент. Пробел перед `=` (например ради
# выравнивания) разрывает его на два, и ble-face ругается `invalid left-hand
# side ''`. Поэтому выравнивание — только справа, после значения.

# --- Синтаксис ---
ble-face \
    syntax_default=none              \
    syntax_command=fg=green          \
    syntax_quoted=fg=green           \
    syntax_quotation=fg=green        \
    syntax_escape=fg=magenta         \
    syntax_expr=fg=blue              \
    syntax_error=fg=red              \
    syntax_varname=fg=none           \
    syntax_delimiter=none            \
    syntax_param_expansion=fg=none   \
    syntax_history_expansion=fg=blue \
    syntax_function_name=fg=green    \
    syntax_comment=fg=242            \
    syntax_glob=fg=magenta           \
    syntax_brace=none                \
    syntax_tilde=none                \
    syntax_document=fg=242           \
    syntax_document_begin=fg=242

# --- Команды ---
ble-face \
    command_builtin_dot=fg=green        \
    command_builtin=fg=green            \
    command_alias=fg=green              \
    command_function=fg=green           \
    command_file=fg=green               \
    command_keyword=fg=green            \
    command_jobs=fg=green               \
    command_directory=fg=blue,underline \
    command_suffix=fg=green             \
    command_suffix_new=fg=red

# --- Имена файлов ---
ble-face \
    filename_directory=fg=blue,underline        \
    filename_directory_sticky=fg=blue,underline \
    filename_link=fg=cyan,underline             \
    filename_orphan=fg=red,underline            \
    filename_setuid=underline                   \
    filename_setgid=underline                   \
    filename_executable=fg=green,underline      \
    filename_other=underline                    \
    filename_socket=fg=cyan,underline           \
    filename_pipe=fg=yellow,underline           \
    filename_character=underline                \
    filename_block=underline                    \
    filename_warning=fg=red,underline           \
    filename_url=fg=blue,underline              \
    filename_ls_colors=underline

# --- Переменные ---
ble-face \
    varname_unset=fg=red      \
    varname_empty=fg=cyan     \
    varname_number=none       \
    varname_expr=fg=blue      \
    varname_array=fg=cyan     \
    varname_hash=fg=cyan      \
    varname_readonly=fg=cyan  \
    varname_transform=fg=cyan \
    varname_export=fg=cyan    \
    varname_new=none

# --- Аргументы ---
ble-face \
    argument_option=fg=cyan \
    argument_error=fg=red

# --- Регионы и UI ---
ble-face \
    region=bg=238                       \
    region_target=bg=238                \
    region_match=bg=238                 \
    region_insert=bg=238                \
    disabled=fg=242                     \
    overwrite_mode=fg=black,bg=cyan     \
    auto_complete=fg=245                \
    menu_filter_input=fg=white,bg=black \
    prompt_status_line=fg=white,bg=238  \
    cmdinfo_cd_cdpath=fg=blue           \
    vbell=reverse                       \
    vbell_flash=reverse                 \
    vbell_erase=bg=238

# --- fzf ---
#
# Биндинги (C-r, C-t, M-c) и completion по `**` подключаются ТОЛЬКО отсюда,
# модулями самого ble.sh. Штатный `eval "$(fzf --bash)"` в .bashrc так не
# работает: ble.sh заменяет собой readline, и bind'ы fzf либо не срабатывают,
# либо рвут отрисовку строки. Модули оборачивают функции fzf так, чтобы те
# отдавали терминал ble.sh и возвращали обратно. Запасной путь на случай, когда
# ble.sh не загрузился, лежит в ~/.config/bash/rc.sh.
#
# Каталог с shell-скриптами fzf модуль находит сам: пакет Ubuntu кладёт их в
# /usr/share/doc/fzf/examples, это один из путей, которые он проверяет. А когда
# fzf стоит голым бинарником (как его и ставит modules/core/update), скриптов
# рядом нет вовсе — тогда ble.sh для версий >= 0.48 переходит на
# `fzf --bash` сам. Если однажды не сработает — задать руками
# _ble_contrib_fzf_base перед ble-import.
#
# -d (отложенная загрузка) тут не оптимизация, а требование порядка:
# fzf-completion обязан грузиться ПОСЛЕ bash-completion, а тот подключается в
# rc.sh уже после ble.sh. С -d модуль дожидается конца инициализации.
#
# Гард по тому же принципу, что у ble.sh и starship в rc.sh: без fzf в системе
# модули печатают «ble/contrib/integration: 'fzf' not found.» на КАЖДЫЙ старт
# шелла, по строке на модуль. Ровно это и вылезало в свежем devsy-контейнере,
# где fzf пакетом не стоит.
#
# type -P, а не command -v: нужен именно бинарник в PATH.
#
# Момент проверки критичен, и когда-то он был выбран неверно. Раньше здесь
# стояло «безопасно, потому что fzf ставится пакетом в /usr/bin, а ~/.local/bin
# rc.sh прописывает позже» — но fzf как раз и ставится установщиком в
# ~/.local/bin, так что проверка промахивалась и интеграция молча отключалась.
# Теперь rc.sh правит PATH ДО загрузки ble.sh, и на момент этой строки
# ~/.local/bin уже на месте. Менять тот порядок обратно нельзя.
if type -P fzf >/dev/null 2>&1; then
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
fi

# Keep Enter executing the command even when ble.sh enters multiline mode.
ble-bind -m emacs -f 'C-m' accept-line
ble-bind -m emacs -f 'RET' accept-line
ble-bind -m vi_imap -f 'C-m' accept-line
ble-bind -m vi_imap -f 'RET' accept-line
