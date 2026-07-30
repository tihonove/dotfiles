#!/bin/sh
# Аналог `cage -m last`: если подключён ЛЮБОЙ внешний выход — оставить только его
# (погасить экран ноута eDP-1). Если внешних нет — вернуть eDP-1.
# Запускается из ~/.config/sway/config и слушает события подключения мониторов.
# Действует только на изменение состояния (без лишних команд → без циклов).

apply() {
    outs=$(swaymsg -t get_outputs)
    ext=$(printf '%s' "$outs" | jq -r '[.[] | select(.name != "eDP-1")] | length')
    edp=$(printf '%s' "$outs" | jq -r '.[] | select(.name == "eDP-1") | .active')
    if [ "${ext:-0}" -gt 0 ] 2>/dev/null; then
        [ "$edp" = "true" ]  && swaymsg output eDP-1 disable >/dev/null
    else
        [ "$edp" = "false" ] && swaymsg output eDP-1 enable  >/dev/null
    fi
}

apply
swaymsg -m -t subscribe '["output"]' | while read -r _event; do
    apply
done
