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

# Keep Enter executing the command even when ble.sh enters multiline mode.
ble-bind -m emacs -f 'C-m' accept-line
ble-bind -m emacs -f 'RET' accept-line
ble-bind -m vi_imap -f 'C-m' accept-line
ble-bind -m vi_imap -f 'RET' accept-line
