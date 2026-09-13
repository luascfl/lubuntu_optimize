#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-all}"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  printf 'rode este script como o usuario da sessao grafica, nao como root\n' >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_HOME="${TARGET_HOME:-$HOME}"
INSTALL_BIN="$TARGET_HOME/.local/bin/gvfs_mtp_automount.py"
SERVICE_NAME="gvfs-mtp-automount.service"
TIMER_NAME="gvfs-mtp-automount.timer"
SERVICE_PATH="$TARGET_HOME/.config/systemd/user/$SERVICE_NAME"
TIMER_PATH="$TARGET_HOME/.config/systemd/user/$TIMER_NAME"
GVFS_DIR="/run/user/$(id -u)/gvfs"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'dependencia ausente: %s\n' "$1" >&2
    exit 1
  }
}

install_fix() {
  need python3
  need gio
  need systemctl

  mkdir -p "$(dirname "$INSTALL_BIN")" "$(dirname "$SERVICE_PATH")"

  cat > "$INSTALL_BIN" <<'PY'
#!/usr/bin/env python3
import json
import os
import re
import subprocess
import time
from pathlib import Path

BACKOFF_SECONDS = 60
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "gvfs-mtp-automount"
STATE_PATH = CACHE_DIR / "state.json"
VOLUME_RE = re.compile(r"^Volume\(\d+\):")
TOP_LEVEL_MOUNT_RE = re.compile(r"^Mount\(\d+\):")
NESTED_MOUNT_RE = re.compile(r"^\s+Mount\(\d+\):")


def load_state() -> dict:
    try:
        return json.loads(STATE_PATH.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state: dict) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True))


def parse_gio_mounts() -> list[dict]:
    result = subprocess.run(["gio", "mount", "-li"], check=True, capture_output=True, text=True)
    volumes: list[dict] = []
    current: dict | None = None

    def flush() -> None:
        nonlocal current
        if current is not None:
            volumes.append(current)
            current = None

    for raw_line in result.stdout.splitlines():
        line = raw_line.rstrip("\n")
        stripped = line.strip()

        if VOLUME_RE.match(line):
            flush()
            current = {
                "mtp": False,
                "activation_root": None,
                "can_mount": False,
                "mounted": False,
            }
            continue

        if current is None:
            continue

        if TOP_LEVEL_MOUNT_RE.match(line):
            flush()
            continue

        if NESTED_MOUNT_RE.match(line):
            current["mounted"] = True
            continue

        if stripped.startswith("Type:") and "GProxyVolumeMonitorMTP" in stripped:
            current["mtp"] = True
            continue

        if stripped.startswith("activation_root="):
            current["activation_root"] = stripped.split("=", 1)[1]
            continue

        if stripped.startswith("can_mount="):
            current["can_mount"] = stripped.endswith("1")
            continue

    flush()
    return volumes


def attempt_mount(root: str, previous: dict | None) -> tuple[bool, dict | None]:
    completed = subprocess.run(["gio", "mount", root], check=False, capture_output=True, text=True)
    stderr = completed.stderr.strip()

    if completed.returncode == 0:
        print(f"mounted {root}")
        return True, None

    next_state = {
        "last_attempt": time.time(),
        "last_error": stderr,
        "last_rc": completed.returncode,
    }

    if previous is None or previous.get("last_error") != stderr or previous.get("last_rc") != completed.returncode:
        message = stderr.splitlines()[0] if stderr else f"gio mount exited {completed.returncode}"
        print(f"mount failed for {root}: {message}")

    return False, next_state


def main() -> int:
    now = time.time()
    state = load_state()
    visible_roots: set[str] = set()

    for volume in parse_gio_mounts():
        if not volume["mtp"]:
            continue

        root = volume["activation_root"]
        if not root:
            continue

        visible_roots.add(root)

        if volume["mounted"] or not volume["can_mount"]:
            state.pop(root, None)
            continue

        previous = state.get(root)
        if previous and now - previous.get("last_attempt", 0) < BACKOFF_SECONDS:
            continue

        _, next_state = attempt_mount(root, previous)
        if next_state is None:
            state.pop(root, None)
        else:
            state[root] = next_state

    for root in list(state):
        if root not in visible_roots:
            state.pop(root, None)

    save_state(state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

  chmod +x "$INSTALL_BIN"

  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Auto-mount visible MTP volumes through GIO
After=gvfs-daemon.service gvfs-mtp-volume-monitor.service

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 $INSTALL_BIN
EOF

  cat > "$TIMER_PATH" <<'EOF'
[Unit]
Description=Retry MTP auto-mount when GVFS misses it

[Timer]
OnActiveSec=5s
OnUnitActiveSec=20s
AccuracySec=2s
Persistent=false

[Install]
WantedBy=timers.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable --now "$TIMER_NAME" >/dev/null
  systemctl --user start "$SERVICE_NAME" >/dev/null || true

  printf 'fix instalado a partir de %s\n' "$SCRIPT_DIR"
  printf 'script ativo: %s\n' "$INSTALL_BIN"
  printf 'service: %s\n' "$SERVICE_PATH"
  printf 'timer: %s\n' "$TIMER_PATH"
  printf 'status rapido:\n'
  systemctl --user status "$TIMER_NAME" "$SERVICE_NAME" --no-pager || true
}

analyze_gio_snapshot() {
  local snapshot="$1"
  python3 - "$snapshot" "$GVFS_DIR" <<'PY'
from pathlib import Path
import re
import sys

snapshot = Path(sys.argv[1])
gvfs_dir = Path(sys.argv[2])
text = snapshot.read_text(encoding='utf-8')
volume_re = re.compile(r'^Volume\(\d+\):')
top_mount_re = re.compile(r'^Mount\(\d+\):')
nested_mount_re = re.compile(r'^\s+Mount\(\d+\):')
volumes = []
current = None


def push(curr):
    if curr is not None:
        volumes.append(curr)


for raw_line in text.splitlines():
    line = raw_line.rstrip('\n')
    stripped = line.strip()
    if volume_re.match(line):
        push(current)
        current = {"name": line.split(':', 1)[1].strip(), "mtp": False, "activation_root": None, "mounted": False, "can_mount": False}
        continue
    if current is None:
        continue
    if top_mount_re.match(line):
        push(current)
        current = None
        continue
    if nested_mount_re.match(line):
        current["mounted"] = True
        continue
    if stripped.startswith('Type:') and 'GProxyVolumeMonitorMTP' in stripped:
        current["mtp"] = True
        continue
    if stripped.startswith('activation_root='):
        current["activation_root"] = stripped.split('=', 1)[1]
        continue
    if stripped.startswith('can_mount='):
        current["can_mount"] = stripped.endswith('1')
        continue
push(current)
mtp = [v for v in volumes if v['mtp']]
if not mtp:
    print('[ok] nenhum volume MTP visivel agora, instalacao pode ser validada sem aparelho conectado')
    raise SystemExit(10)
for volume in mtp:
    root = volume['activation_root'] or '(sem activation_root)'
    state = 'mounted' if volume['mounted'] else 'unmounted'
    print(f"[info] {volume['name']} -> {root} [{state}]")
if gvfs_dir.exists():
    print(f"[info] conteudo atual de {gvfs_dir}:")
    for child in sorted(gvfs_dir.iterdir()):
        print(f"  - {child.name}")
else:
    print(f"[warn] diretorio gvfs ausente: {gvfs_dir}")
raise SystemExit(0 if any(v['mounted'] for v in mtp) else 20)
PY
  local py_status=$?
  return "$py_status"
}


run_verify() {
  need python3
  need gio
  need systemctl
  need lsusb

  local status=0
  local py_status=0
  local snapshot

  printf '== arquivos instalados ==\n'
  for path in \
    "$INSTALL_BIN" \
    "$SERVICE_PATH" \
    "$TIMER_PATH"
  do
    if [[ -f "$path" ]]; then
      printf '[ok] %s\n' "$path"
    else
      printf '[fail] ausente: %s\n' "$path"
      status=1
    fi
  done

  printf '\n== systemd user ==\n'
  if systemctl --user is-enabled "$TIMER_NAME" >/dev/null 2>&1; then
    printf '[ok] timer habilitado\n'
  else
    printf '[fail] timer nao habilitado\n'
    status=1
  fi

  if systemctl --user is-active "$TIMER_NAME" >/dev/null 2>&1; then
    printf '[ok] timer ativo\n'
  else
    printf '[fail] timer nao ativo\n'
    status=1
  fi

  if systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
    printf '[ok] service ativo agora\n'
  else
    printf '[ok] service ocioso entre execucoes\n'
  fi

  printf '\n== usb ==\n'
  lsusb

  snapshot="$(mktemp)"
  trap 'rm -f "$snapshot"' RETURN
  gio mount -li > "$snapshot"

  printf '\n== resumo gio/gvfs ==\n'
  set +e
  analyze_gio_snapshot "$snapshot"
  py_status=$?
  set -e

  if [[ "$py_status" -eq 20 ]]; then
    printf '[warn] aparelho MTP detectado, mas ainda nao montado, tentando montar agora\n'
    systemctl --user start "$SERVICE_NAME" >/dev/null || true
    sleep 1
    gio mount -li > "$snapshot"
    printf '\n== rechecagem apos tentativa de mount ==\n'
    set +e
    analyze_gio_snapshot "$snapshot"
    py_status=$?
    set -e
  fi

  trap - RETURN
  rm -f "$snapshot"

  case "$py_status" in
    0)
      printf '[ok] ha volume MTP montado\n'
      ;;
    10)
      printf '[ok] instalacao validada, sem aparelho MTP conectado no momento\n'
      ;;
    20)
      printf '[fail] aparelho MTP detectado, mas ainda nao montado\n'
      printf 'dica: systemctl --user start %s\n' "$SERVICE_NAME"
      status=1
      ;;
    *)
      printf '[fail] erro ao analisar o estado do gio/gvfs\n'
      status=1
      ;;
  esac

  printf '\n== status detalhado ==\n'
  systemctl --user status "$TIMER_NAME" "$SERVICE_NAME" --no-pager || true

  return "$status"
}

usage() {
  printf 'uso: %s [fix|verify|all]\n' "$(basename "$0")" >&2
}

case "$MODE" in
  fix)
    install_fix
    ;;
  verify)
    run_verify
    ;;
  all)
    install_fix
    printf '\n'
    run_verify
    ;;
  *)
    usage
    exit 1
    ;;
esac
