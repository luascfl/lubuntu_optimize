#!/usr/bin/env bash
# Install the Dunst history indicator and start it from IceWM.
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly source_script="$script_dir/dunst-tray-history.py"
readonly source_notifier="$script_dir/notify-qterminal.sh"
readonly source_popup_clicks="$script_dir/dunst-popup-clicks.conf"
readonly target_home="${TARGET_HOME:-$HOME}"
readonly target_script="$target_home/.local/bin/dunst-tray-history"
readonly target_notifier="$target_home/.local/bin/notify-qterminal"
readonly popup_clicks_config="$target_home/.config/dunst/dunstrc.d/90-popup-clicks.conf"
readonly startup_file="${ICEWM_STARTUP:-$target_home/.icewm/startup}"
readonly start_marker="# BEGIN dunst tray history"
readonly end_marker="# END dunst tray history"
readonly process_pattern="$target_script( |$)"

temp_file=""
cleanup() {
    [[ -z "$temp_file" ]] || rm -f -- "$temp_file"
}
trap cleanup EXIT

require_runtime() {
    command -v dunstctl >/dev/null 2>&1 || {
        printf 'Erro: dunstctl não foi encontrado. Instale e inicie o Dunst primeiro.\n' >&2
        exit 1
    }
    [[ -x /usr/bin/python3 ]] || {
        printf 'Erro: /usr/bin/python3 não foi encontrado.\n' >&2
        exit 1
    }
    /usr/bin/python3 -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" || {
        printf 'Erro: GTK Python indisponível. Instale python3-gi e gir1.2-gtk-3.0.\n' >&2
        exit 1
    }
}

remove_managed_block() {
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { inside = 1; next }
        $0 == end { inside = 0; next }
        !inside { print }
    ' "$startup_file" > "$temp_file"
}

write_startup() {
    mkdir -p -- "$(dirname -- "$startup_file")"
    [[ -f "$startup_file" ]] || printf '#!/bin/sh\n' > "$startup_file"
    [[ ! -L "$startup_file" ]] || {
        printf 'Erro: recusa alterar startup simbólico: %s\n' "$startup_file" >&2
        exit 1
    }

    local backup_file="${startup_file}.dunst-tray-history.bak"
    [[ -e "$backup_file" ]] || cp -- "$startup_file" "$backup_file"

    temp_file="$(mktemp "${startup_file}.tmp.XXXXXX")"
    remove_managed_block
    cat >> "$temp_file" <<EOF

$start_marker
# Dunst mantém o histórico; este ícone da tray permite reler e marcar avisos.
if command -v dunstctl >/dev/null 2>&1 && [ -r '$popup_clicks_config' ]; then
  dunstctl reload /etc/xdg/dunst/dunstrc '$popup_clicks_config' >/dev/null 2>&1 || true
fi
if [ -x '$target_script' ] && ! pgrep -f '$process_pattern' >/dev/null; then
  '$target_script' >/dev/null 2>&1 &
fi
$end_marker
EOF
    mv -- "$temp_file" "$startup_file"
    temp_file=""
    chmod 0755 "$startup_file"
    sh -n "$startup_file"
}

start_indicator() {
    if pgrep -f "$process_pattern" >/dev/null; then
        pkill -f "$process_pattern"
        printf 'Indicador em execução reiniciado com a versão atual.\n'
    else
        printf 'Indicador iniciado. Ele aparecerá na tray do IceWM.\n'
    fi
    "$target_script" >/dev/null 2>&1 &
}

main() {
    require_runtime
    [[ -f "$source_script" && -f "$source_notifier" && -f "$source_popup_clicks" ]] || {
        printf 'Erro: arquivos-fonte do Dunst ausentes em %s\n' "$script_dir" >&2
        exit 1
    }

    install -D -m 0755 "$source_script" "$target_script"
    install -D -m 0755 "$source_notifier" "$target_notifier"
    install -D -m 0644 "$source_popup_clicks" "$popup_clicks_config"
    dunstctl reload /etc/xdg/dunst/dunstrc "$popup_clicks_config"
    write_startup
    start_indicator
    printf 'Instalação concluída. Clique no ícone para abrir o histórico do Dunst.\n'
}

main "$@"
