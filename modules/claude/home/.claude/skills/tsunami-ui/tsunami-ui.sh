#!/usr/bin/env bash
# Start the Tsunami UI dev server of any nebo checkout/worktree in a new tmux pane.
# Only one frontend runs on the machine: the previous one (from any worktree) is stopped first.
#
#   tsunami-ui [-g|--gen] [-w|--window] [DIR]
#
# DIR       any path inside the checkout (default: cwd)
# --gen     force `fdk generate` (it also runs when fdk_start.sh is missing)
# --window  open a background tmux window instead of splitting the current pane
set -euo pipefail

gen=0 mode=split dir=.
while [ $# -gt 0 ]; do
    case "$1" in
        -g|--gen) gen=1 ;;
        -w|--window) mode=window ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) dir="$1" ;;
    esac
    shift
done

[ -n "${TMUX:-}" ] || { echo "tsunami-ui: not inside tmux" >&2; exit 1; }

root=$(git -C "$dir" rev-parse --show-toplevel)
app="$root/ui/gold/applications/tsunami"
[ -d "$app" ] || { echo "tsunami-ui: no $app" >&2; exit 1; }
name=$(basename "$root")

for p in $(tmux list-panes -a -F '#{pane_id} #{pane_title}' | awk '$2 == "tsunami-ui" {print $1}'); do
    tmux kill-pane -t "$p"
done
pkill -f 'nebpack/lib/esm/cli.js start fullstack' && sleep 1 || true

# Every worktree has its own bazel output base, hence its own node binary; 443 needs the capability on it.
cmd="echo '▶ $name → https://local.tsunami.nebius.dev'"
# fdk fetches .secret.json via npc under its TUI, which swallows the login link — log in visibly first.
gencmd="npc iam whoami --profile testing >/dev/null && $root/bazel run //ui_infra/applications/fdk -- generate --skip-host"
if [ "$gen" = 1 ]; then
    cmd+="; $gencmd"
else
    cmd+="; [ -x fdk_start.sh ] || { $gencmd; }"
fi
cmd+=" && node=\$(grep -o '/[^ ]*/bin/node' fdk_start.sh)"
cmd+=" && { getcap \$node | grep -q cap_net_bind_service || sudo setcap cap_net_bind_service=ep \$node; }"
cmd+=" && ./fdk_start.sh; echo; echo \"[tsunami-ui exited: \$?] press Enter\"; read -r"

if [ "$mode" = window ]; then
    pane=$(tmux new-window -d -P -F '#{pane_id}' -n "tsunami-ui" -c "$app" bash -lc "$cmd")
else
    pane=$(tmux split-window -h -d -P -F '#{pane_id}' -c "$app" bash -lc "$cmd")
fi
tmux select-pane -t "$pane" -T "tsunami-ui $name"

echo "tsunami-ui: $name in tmux pane $pane → https://local.tsunami.nebius.dev"
