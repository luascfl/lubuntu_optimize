#!/usr/bin/env bash
# Enable Discover update notifications in IceWM without starting KDE services.
set -euo pipefail

readonly notifier_package="plasma-discover-notifier"
readonly notifier_binary="/usr/lib/x86_64-linux-gnu/libexec/DiscoverNotifier"
readonly startup_file="${ICEWM_STARTUP:-$HOME/.icewm/startup}"
readonly managed_marker="# Discover's packaged autostart is limited to KDE sessions. Start its update"
readonly notifier_process_pattern='/DiscoverNotifier( |$)'

tmp_file=""
cleanup() {
    [[ -z "$tmp_file" ]] || rm -f -- "$tmp_file"
}
trap cleanup EXIT

if [[ "$(dpkg-query -W -f='${db:Status-Status}' "$notifier_package" 2>/dev/null || true)" != "installed" ]]; then
    printf 'Erro: o pacote %s não está instalado.\n' "$notifier_package" >&2
    printf 'Instale-o com: sudo apt install %s\n' "$notifier_package" >&2
    exit 1
fi

if [[ ! -x "$notifier_binary" ]]; then
    printf 'Erro: executável do Discover não encontrado em %s.\n' "$notifier_binary" >&2
    exit 1
fi

if [[ -L "$startup_file" ]]; then
    printf 'Erro: recusa alterar startup simbólico: %s\n' "$startup_file" >&2
    exit 1
fi

mkdir -p -- "$(dirname -- "$startup_file")"
[[ -f "$startup_file" ]] || printf '#!/bin/sh\n' > "$startup_file"

block_is_current() {
    awk -v marker="$managed_marker" '
        $0 == marker { in_block = 1; next }
        in_block && $0 == "   ! pgrep -f '\''/DiscoverNotifier( |$)'\'' >/dev/null; then" {
            has_process_guard = 1
            next
        }
        in_block && $0 == "fi" {
            if (has_process_guard) found = 1
            in_block = 0
            has_process_guard = 0
        }
        END { exit(found ? 0 : 1) }
    ' "$startup_file"
}

if block_is_current; then
    printf 'Autostart do Discover já está configurado em %s.\n' "$startup_file"
else
    tmp_file="$(mktemp "$(dirname -- "$startup_file")/.startup.XXXXXX")"
    awk -v marker="$managed_marker" '
        $0 == marker { skipping = 1; next }
        skipping {
            if ($0 == "fi") skipping = 0
            next
        }
        { print }
    ' "$startup_file" > "$tmp_file"

    cat >> "$tmp_file" <<'EOF'

# Discover's packaged autostart is limited to KDE sessions. Start its update
# notifier explicitly so IceWM displays available software updates in the tray.
if [ -x /usr/lib/x86_64-linux-gnu/libexec/DiscoverNotifier ] &&
   ! pgrep -f '/DiscoverNotifier( |$)' >/dev/null; then
  /usr/lib/x86_64-linux-gnu/libexec/DiscoverNotifier --check-delay 20 >/dev/null 2>&1 &
fi
EOF

    if ! sh -n "$tmp_file"; then
        printf 'Erro: a configuração gerada para %s é inválida.\n' "$startup_file" >&2
        exit 1
    fi

    if [[ -s "$startup_file" ]]; then
        backup_file="${startup_file}.bak.$(date +%Y%m%d-%H%M%S)"
        cp -- "$startup_file" "$backup_file"
        printf 'Backup criado em %s.\n' "$backup_file"
    fi
    mv -- "$tmp_file" "$startup_file"
    tmp_file=""
    printf 'Autostart do Discover configurado em %s.\n' "$startup_file"
fi

sh -n "$startup_file"

if pgrep -f "$notifier_process_pattern" >/dev/null; then
    printf 'DiscoverNotifier já está em execução.\n'
else
    "$notifier_binary" --check-delay 20 >/dev/null 2>&1 &
    printf 'DiscoverNotifier iniciado para a sessão atual.\n'
fi

printf 'Validação concluída. O Discover notificará quando encontrar atualizações.\n'
