#!/usr/bin/env bash
# Install a weekly, non-interactive Topgrade timer for this user.
set -euo pipefail

readonly script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly user_name="$(id -un)"
readonly topgrade_binary="$HOME/.cargo/bin/topgrade"
readonly config_dir="$HOME/.config/topgrade"
readonly timer_config="$config_dir/topgrade-weekly.toml"
readonly unit_dir="$HOME/.config/systemd/user"
readonly service_file="$unit_dir/topgrade-weekly.service"
readonly timer_file="$unit_dir/topgrade-weekly.timer"
readonly sudoers_source="$script_dir/topgrade-weekly.sudoers"
readonly sudoers_destination="/etc/sudoers.d/topgrade-weekly-$user_name"
readonly log_file="$script_dir/reports/topgrade-weekly.log"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'Erro: comando obrigatório ausente: %s\n' "$1" >&2
        exit 1
    fi
}

write_file_if_changed() {
    local destination="$1"
    local temporary

    temporary="$(mktemp "$(dirname -- "$destination")/.${destination##*/}.XXXXXX")"
    cat > "$temporary"

    if cmp -s -- "$temporary" "$destination" 2>/dev/null; then
        rm -f -- "$temporary"
        printf 'Sem alteração: %s\n' "$destination"
        return
    fi

    if [[ -f "$destination" ]]; then
        cp -- "$destination" "${destination}.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    mv -- "$temporary" "$destination"
    printf 'Configurado: %s\n' "$destination"
}

require_command sudo
require_command visudo
require_command systemctl
require_command flock

if [[ ! -x "$topgrade_binary" ]]; then
    printf 'Erro: Topgrade não encontrado em %s.\n' "$topgrade_binary" >&2
    exit 1
fi

mkdir -p -- "$config_dir" "$unit_dir" "$(dirname -- "$log_file")"

cat <<EOF | write_file_if_changed "$timer_config"
[misc]
# Background jobs cannot answer a sudo prompt. Privileged commands below are
# narrowly authorized by /etc/sudoers.d/topgrade-weekly-$user_name.
pre_sudo = false
assume_yes = true
no_retry = true
set_title = false
disable = ["firmware", "node", "claude_code"]

[flatpak]
use_sudo = true

[commands]
"NPM global packages" = "$script_dir/update_npm_globals_serial.sh"
"Claude Code" = "$script_dir/update_claude_code.sh"
EOF

cat <<EOF | write_file_if_changed "$service_file"
[Unit]
Description=Weekly non-interactive Topgrade update
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$script_dir
ExecStart=/usr/bin/flock -n $HOME/.cache/topgrade-weekly.lock $topgrade_binary --config $timer_config --no-tmux
TimeoutStartSec=4h
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
StandardOutput=append:$log_file
StandardError=append:$log_file
EOF

cat <<EOF | write_file_if_changed "$timer_file"
[Unit]
Description=Run Topgrade weekly in the background

[Timer]
OnCalendar=Sun *-*-* 03:00
Persistent=true
RandomizedDelaySec=30m

[Install]
WantedBy=timers.target
EOF

cat <<EOF > "$sudoers_source"
# Managed by $script_dir/setup_topgrade_weekly_timer.sh.
# Permit only the commands Topgrade needs for this scheduled service.
Cmnd_Alias TOPGRADE_WEEKLY = /usr/bin/apt update, \
    /usr/bin/apt dist-upgrade -y, \
    /usr/bin/apt-get update, \
    /usr/bin/apt-get dist-upgrade -y, \
    /usr/bin/snap refresh, \
    /usr/bin/flatpak update --system -y
$user_name ALL=(root) NOPASSWD: TOPGRADE_WEEKLY
EOF
chmod 0644 "$sudoers_source"

visudo -cf "$sudoers_source"
printf 'Instalando regra sudo restrita em %s.\n' "$sudoers_destination"
sudo install -o root -g root -m 0440 "$sudoers_source" "$sudoers_destination"
sudo visudo -cf "$sudoers_destination"

systemctl --user daemon-reload
systemctl --user enable --now topgrade-weekly.timer

printf 'Validando os comandos que o timer executará, sem atualizar o sistema...\n'
dry_run="$($topgrade_binary --config "$timer_config" --dry-run --no-tmux 2>&1)"
printf '%s\n' "$dry_run"

if [[ "$dry_run" == *"Firmware upgrades"* ]] ||
   [[ "$dry_run" == *"sudo -v"* ]] ||
   { [[ "$dry_run" != *"apt dist-upgrade -y"* ]] &&
     [[ "$dry_run" != *"apt-get dist-upgrade -y"* ]]; } ||
   [[ "$dry_run" != *"snap refresh"* ]] ||
   [[ "$dry_run" != *"flatpak update --system -y"* ]]; then
    printf 'Erro: a configuração do timer não corresponde ao escopo aprovado.\n' >&2
    exit 1
fi

printf 'Timer instalado. A próxima execução será informada por:\n'
systemctl --user list-timers topgrade-weekly.timer --all --no-pager
printf 'Log: %s\n' "$log_file"
