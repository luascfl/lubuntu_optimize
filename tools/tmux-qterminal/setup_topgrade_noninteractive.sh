#!/usr/bin/env bash
# Configure Topgrade for non-interactive supported updates while retaining sudo.
set -euo pipefail

readonly config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
readonly config_file="$config_dir/topgrade.toml"
readonly backup_suffix=".bak.$(date +%Y%m%d-%H%M%S)"

tmp_file=""
cleanup() {
    [[ -z "$tmp_file" ]] || rm -f -- "$tmp_file"
}
trap cleanup EXIT

if ! command -v topgrade >/dev/null 2>&1; then
    printf 'Erro: topgrade não está instalado ou não está no PATH.\n' >&2
    exit 1
fi

mkdir -p -- "$config_dir"
[[ -f "$config_file" ]] || : > "$config_file"

tmp_file="$(mktemp "$config_dir/.topgrade.toml.XXXXXX")"

awk '
function write_missing() {
    if (!seen_pre_sudo) print "pre_sudo = true"
    if (!seen_assume_yes) print "assume_yes = true"
    if (!seen_no_retry) print "no_retry = true"
}

/^\[[^]]+\][[:space:]]*$/ {
    if (in_misc) write_missing()
    in_misc = ($0 == "[misc]")
    if (in_misc) found_misc = 1
    print
    next
}

in_misc && /^[[:space:]]*pre_sudo[[:space:]]*=/ {
    print "pre_sudo = true"
    seen_pre_sudo = 1
    next
}

in_misc && /^[[:space:]]*assume_yes[[:space:]]*=/ {
    print "assume_yes = true"
    seen_assume_yes = 1
    next
}

in_misc && /^[[:space:]]*no_retry[[:space:]]*=/ {
    print "no_retry = true"
    seen_no_retry = 1
    next
}

{ print }

END {
    if (in_misc) {
        write_missing()
    } else if (!found_misc) {
        print ""
        print "[misc]"
        print "pre_sudo = true"
        print "assume_yes = true"
        print "no_retry = true"
    }
}
' "$config_file" > "$tmp_file"

if cmp -s -- "$config_file" "$tmp_file"; then
    printf 'Topgrade já está configurado em %s.\n' "$config_file"
else
    if [[ -s "$config_file" ]]; then
        backup_file="${config_file}${backup_suffix}"
        cp -- "$config_file" "$backup_file"
        printf 'Backup criado em %s.\n' "$backup_file"
    fi
    mv -- "$tmp_file" "$config_file"
    tmp_file=""
    printf 'Configuração aplicada em %s.\n' "$config_file"
fi

printf 'Validando a execução sem alterações no sistema...\n'
if ! dry_run="$(topgrade --dry-run --no-tmux --only system 2>&1)"; then
    printf '%s\n' "$dry_run" >&2
    exit 1
fi
printf '%s\n' "$dry_run"

if [[ "$dry_run" != *"sudo -v"* ]] || [[ "$dry_run" != *"apt-get dist-upgrade -y"* ]]; then
    printf 'Erro: o Topgrade não carregou a configuração não interativa esperada.\n' >&2
    exit 1
fi

printf 'Validação concluída: o Topgrade pedirá sudo uma vez e atualizará APT com -y.\n'
