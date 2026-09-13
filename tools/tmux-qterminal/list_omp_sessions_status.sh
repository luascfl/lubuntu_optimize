#!/usr/bin/env bash
set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
SESSIONS_DIR="$AGENT_DIR/sessions"
TERMINAL_DIR="$AGENT_DIR/terminal-sessions"

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "Erro: pasta de sessões não encontrada: $SESSIONS_DIR" >&2
  exit 1
fi

if [ ! -d "$TERMINAL_DIR" ]; then
  echo "Erro: pasta de sessões de terminal não encontrada: $TERMINAL_DIR" >&2
  exit 1
fi

all_file=$(mktemp)
active_file=$(mktemp)

cleanup() {
  rm -f "$all_file" "$active_file"
}
trap cleanup EXIT

find "$SESSIONS_DIR" -type f -name '*.jsonl' | sort -r > "$all_file"

for tty in $(ps -eo tty=,cmd= | awk '$1 ~ /^pts\/[0-9]+$/ && $0 ~ /[[:space:]\/]omp([[:space:]]|$)/ { print $1 }' | sort -u); do
  term_file="$TERMINAL_DIR/${tty/pts\//pts-}"
  [ -f "$term_file" ] && sed -n '2p' "$term_file"
done | sort -u > "$active_file"

printf '%-8s | %-16s | %-20s | %-42s | %s\n' "status" "id" "data_utc" "pasta" "assunto"
printf '%-8s-+-%-16s-+-%-20s-+-%-42s-+-%s\n' "--------" "----------------" "--------------------" "------------------------------------------" "----------------"

while IFS= read -r sess; do
  [ -z "$sess" ] && continue

  status="fechada"
  if grep -Fxq "$sess" "$active_file"; then
    status="aberta"
  fi

  first=$(sed -n '1p' "$sess")

  id=$(printf '%s\n' "$first" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
  ts=$(printf '%s\n' "$first" | sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p')
  cwd=$(printf '%s\n' "$first" | sed -n 's/.*"cwd":"\([^"]*\)".*/\1/p')
  title=$(printf '%s\n' "$first" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')

  if [ -z "$id" ]; then
    id=$(basename "$sess" .jsonl | sed 's/.*_//')
  fi

  if [ -z "$title" ]; then
    title="(sem título)"
  fi

  if [ -z "$cwd" ]; then
    cwd="(sem cwd)"
  fi

  if [ -z "$ts" ]; then
    ts="(sem data)"
  fi

  printf '%-8s | %-16s | %-20s | %-42s | %s\n' "$status" "$id" "$ts" "$cwd" "$title"
done < "$all_file"
