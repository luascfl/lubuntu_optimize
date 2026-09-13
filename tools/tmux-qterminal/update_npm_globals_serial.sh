#!/usr/bin/env bash
# Update NVM global packages one root package at a time on low-memory systems.
set -euo pipefail

readonly node_version="v22.22.2"
readonly node_root="$HOME/.nvm/versions/node/$node_version"
readonly npm_binary="$node_root/bin/npm"
readonly node_binary="$node_root/bin/node"
readonly mode="${1:---apply}"

case "$mode" in
    --apply|--dry-run) ;;
    *)
        printf 'Uso: %s [--apply|--dry-run]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

if [[ ! -x "$npm_binary" ]] || [[ ! -x "$node_binary" ]]; then
    printf 'Erro: npm ou node do NVM não está disponível em %s.\n' "$node_root" >&2
    exit 1
fi

inventory="$("$npm_binary" ls --location=global --depth=0 --json --silent 2>/dev/null || true)"
if [[ -z "$inventory" ]]; then
    printf 'Erro: não foi possível inventariar os pacotes globais do npm.\n' >&2
    exit 1
fi

mapfile -t packages < <(printf '%s' "$inventory" | "$node_binary" -e '
    let data = "";
    process.stdin.on("data", chunk => data += chunk);
    process.stdin.on("end", () => {
        const dependencies = JSON.parse(data).dependencies ?? {};
        for (const name of Object.keys(dependencies).sort()) {
            if (name !== "npm" && name !== "corepack") console.log(name);
        }
    });
')

if ((${#packages[@]} == 0)); then
    printf 'Nenhum pacote global elegível para atualizar.\n'
    exit 0
fi

printf 'Atualizando %d pacotes globais em série.\n' "${#packages[@]}"
for package in "${packages[@]}"; do
    printf '\n==> %s\n' "$package"
    if [[ "$mode" == "--dry-run" ]]; then
        NPM_CONFIG_ALLOW_REMOTE=all NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=512}" \
            "$npm_binary" install --location=global "$package@latest" --dry-run --loglevel error
    else
        NPM_CONFIG_ALLOW_REMOTE=all NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=512}" \
            "$npm_binary" install --location=global "$package@latest" --loglevel error
    fi
done
