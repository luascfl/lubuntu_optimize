#!/usr/bin/env bash
# Send a QTerminal notification whose native Dunst click focuses the terminal.
set -euo pipefail

summary=${1:?Uso: notify-qterminal.sh "Título" ["Mensagem"]}
body=${2:-}

if command -v dunstify >/dev/null 2>&1; then
    (
        action="$(dunstify -a QTerminal -A 'focus,Focus QTerminal' --block "$summary" "$body" 2>/dev/null || true)"
        if [[ "$action" == "focus" ]] && command -v wmctrl >/dev/null 2>&1; then
            wmctrl -xa qterminal.qterminal >/dev/null 2>&1 || true
        fi
    ) >/dev/null 2>&1 &
else
    notify-send --app-name=QTerminal "$summary" "$body"
fi
