#!/bin/sh
# История буфера обмена — аналог Win+V.
# Показывает список из cliphist через fuzzel (--dmenu), выбранный элемент
# кладёт в буфер и автоматически вставляет в активное окно.
#
# Тонкость: терминалы вставляют по Ctrl+Shift+V, а обычные GUI-поля — по Ctrl+V.
# Поэтому смотрим app_id/class сфокусированного окна и шлём нужную комбинацию.

# Показать историю; fuzzel вернёт выбранную строку (с ведущим id-номером).
chosen=$(cliphist list | fuzzel --dmenu --prompt 'clipboard> ') || exit 0
[ -n "$chosen" ] || exit 0

# Раскодировать выбранный элемент (по id) и положить в буфер обмена.
printf '%s' "$chosen" | cliphist decode | wl-copy

# Узнать окно, которое было активным ДО пикера (fuzzel уже закрылся и вернул
# фокус ему). Для wayland-окон это app_id, для xwayland — window_properties.class.
win=$(swaymsg -t get_tree | jq -r '.. | select(.focused? == true)
        | (.app_id // .window_properties.class // "") | ascii_downcase')

# Дать fuzzel закрыться / вернуть фокус и буферу устаканиться.
sleep 0.12

# Список терминалов, которым нужен Ctrl+Shift+V.
case "$win" in
    kitty|foot|footclient|alacritty|wezterm|org.wezfurlong.wezterm|\
    st|st-256color|xterm|urxvt|rxvt-unicode|konsole|org.kde.konsole|\
    gnome-terminal*|org.gnome.terminal|kgx|org.gnome.console|\
    xfce4-terminal|terminator|tilix|com.mitchellh.ghostty|ghostty)
        wtype -M ctrl -M shift -k v -m shift -m ctrl ;;   # Ctrl+Shift+V
    *)
        wtype -M ctrl -k v -m ctrl ;;                     # Ctrl+V
esac
