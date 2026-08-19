#!/bin/sh
set -eu

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SUDOERS_DIR=${SUDOERS_DIR:-/etc/sudoers.d}
VISUDO_BIN=${VISUDO_BIN:-$(command -v visudo 2>/dev/null || true)}
DEFAULT_PROFILE=tuning

usage() {
  cat <<EOF
Usage:
  sudo $SCRIPT_NAME enable [--profile tuning|full] [--user <name>]
  sudo $SCRIPT_NAME disable [--user <name>]
  sudo $SCRIPT_NAME status [--user <name>]
  $SCRIPT_NAME enable --pty [--profile tuning|full] [--user <name>]

Profiles:
  tuning  Recommended. Grants passwordless sudo only for the ZRAM monitor and
          low-risk tuning commands used by this repository.
  full    Grants passwordless sudo for all commands for the selected user.

Notes:
  - When run with sudo, the default target user is \$SUDO_USER.
  - Set SUDOERS_DIR to test safely against a temporary directory.
  - Use --pty to open a visible terminal and run this script through sudo when
    the current shell cannot show the password prompt.
EOF
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

infer_target_user() {
  if [ -n "${TARGET_USER:-}" ]; then
    return
  fi

  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    TARGET_USER=$SUDO_USER
    return
  fi

  if [ "$(id -u)" -ne 0 ]; then
    TARGET_USER=$(id -un)
    return
  fi

  die "use --user when running as root without SUDO_USER"
}

validate_target_user() {
  case "$TARGET_USER" in
    ''|*[!A-Za-z0-9._-]*)
      die "target user must contain only letters, digits, dot, underscore, or dash"
      ;;
  esac

  id "$TARGET_USER" >/dev/null 2>&1 || die "user '$TARGET_USER' does not exist"
}

require_root_if_needed() {
  if [ "$SUDOERS_DIR" = "/etc/sudoers.d" ] && [ "$(id -u)" -ne 0 ]; then
    die "run this command with sudo when using /etc/sudoers.d"
  fi
}

ensure_visudo() {
  [ -n "$VISUDO_BIN" ] || die "visudo not found in PATH"
  [ -x "$VISUDO_BIN" ] || die "visudo binary '$VISUDO_BIN' is not executable"
}

find_pty_terminal() {
  if [ -n "${PTY_TERMINAL:-}" ]; then
    printf '%s\n' "$PTY_TERMINAL"
    return
  fi

  for terminal in qterminal lxterminal xterm; do
    if command -v "$terminal" >/dev/null 2>&1; then
      command -v "$terminal"
      return
    fi
  done
}

run_with_pty() {
  terminal=$(find_pty_terminal)
  [ -n "$terminal" ] || die "no supported terminal found for --pty"

  if [ "${PTY_DRY_RUN:-0}" = "1" ]; then
    printf 'pty terminal: %s\n' "$terminal"
    printf 'pty command: sudo %s %s --profile %s --user %s\n' "$SCRIPT_DIR/$SCRIPT_NAME" "$ACTION" "$PROFILE" "$TARGET_USER"
    return
  fi

  "$terminal" -e sh -c '
    cd "$1" || exit 1
    shift
    sudo "$@"
    code=$?
    printf "\nPressione Enter para fechar..."
    read _
    exit "$code"
  ' sh "$SCRIPT_DIR" "$SCRIPT_DIR/$SCRIPT_NAME" "$ACTION" --profile "$PROFILE" --user "$TARGET_USER"
}

generate_sudoers() {
  case "$PROFILE" in
    tuning)
      cat <<EOF
# Managed by $SCRIPT_NAME
# User: $TARGET_USER
# Profile: tuning
User_Alias OMPUSER = $TARGET_USER

Cmnd_Alias OMP_TUNING = \
    ${SCRIPT_DIR}/install-zram-monitor.sh, \
    ${SCRIPT_DIR}/apply-cpugov-performance-service.sh, \
    ${SCRIPT_DIR}/optimize.sh, \
    /usr/bin/systemctl start zram-monitor.service, \
    /usr/bin/systemctl restart zram-monitor.service, \
    /usr/bin/systemctl status zram-monitor.service, \
    /usr/bin/systemctl is-active zram-monitor.service, \
    /usr/bin/systemctl reset-failed zram-monitor.service, \
    /usr/bin/systemctl start zram-monitor.timer, \
    /usr/bin/systemctl stop zram-monitor.timer, \
    /usr/bin/systemctl enable zram-monitor.timer, \
    /usr/bin/systemctl enable --now zram-monitor.timer, \
    /usr/bin/systemctl disable zram-monitor.timer, \
    /usr/bin/systemctl status zram-monitor.timer, \
    /usr/bin/systemctl is-active zram-monitor.timer, \
    /usr/bin/systemctl is-enabled zram-monitor.timer, \
    /usr/bin/systemctl restart zramswap, \
    /usr/bin/systemctl status zramswap, \
    /usr/bin/systemctl is-active zramswap, \
    /usr/bin/systemctl restart earlyoom, \
    /usr/bin/systemctl status earlyoom, \
    /usr/bin/systemctl is-active earlyoom, \
    /usr/bin/systemctl daemon-reload, \
    /usr/bin/systemctl enable cpugov-performance.service, \
    /usr/bin/systemctl enable --now cpugov-performance.service, \
    /usr/bin/systemctl start cpugov-performance.service, \
    /usr/bin/systemctl restart cpugov-performance.service, \
    /usr/bin/systemctl status cpugov-performance.service, \
    /usr/bin/systemctl is-enabled cpugov-performance.service, \
    /usr/bin/systemctl show cpugov-performance.service

OMPUSER ALL=(root) NOPASSWD: OMP_TUNING
EOF
      ;;
    full)
      cat <<EOF
# Managed by $SCRIPT_NAME
# User: $TARGET_USER
# Profile: full
$TARGET_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
      ;;
    *)
      die "unknown profile '$PROFILE'"
      ;;
  esac
}

enable_passwordless() {
  ensure_visudo
  require_root_if_needed
  mkdir -p "$SUDOERS_DIR"

  tmp_file=$(mktemp "${TMPDIR:-/tmp}/${SCRIPT_NAME}.XXXXXX")
  trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
  generate_sudoers > "$tmp_file"
  chmod 0440 "$tmp_file"

  "$VISUDO_BIN" -cf "$tmp_file" >/dev/null
  install -m 0440 "$tmp_file" "$SUDOERS_FILE"
  "$VISUDO_BIN" -cf "$SUDOERS_FILE" >/dev/null

  printf 'enabled passwordless sudo for user %s with profile %s\n' "$TARGET_USER" "$PROFILE"
  printf 'sudoers file: %s\n' "$SUDOERS_FILE"
}

disable_passwordless() {
  require_root_if_needed

  if [ -f "$SUDOERS_FILE" ]; then
    rm -f "$SUDOERS_FILE"
    printf 'disabled passwordless sudo for user %s\n' "$TARGET_USER"
    printf 'removed sudoers file: %s\n' "$SUDOERS_FILE"
  else
    printf 'passwordless sudo already disabled for user %s\n' "$TARGET_USER"
    printf 'sudoers file not present: %s\n' "$SUDOERS_FILE"
  fi
}

show_status() {
  if [ -f "$SUDOERS_FILE" ]; then
    printf 'status: enabled\n'
    printf 'sudoers file: %s\n' "$SUDOERS_FILE"
    if [ -r "$SUDOERS_FILE" ]; then
      profile_line=$(python3 - <<'PY' "$SUDOERS_FILE"
import sys
path = sys.argv[1]
profile = 'unknown'
with open(path, 'r', encoding='utf-8') as handle:
    for line in handle:
        if line.startswith('# Profile: '):
            profile = line.split(':', 1)[1].strip()
            break
print(profile)
PY
)
      printf 'profile: %s\n' "$profile_line"
    else
      printf 'profile: unreadable without sudo\n'
    fi
  else
    printf 'status: disabled\n'
    printf 'sudoers file: %s\n' "$SUDOERS_FILE"
  fi
}

ACTION=""
PROFILE=$DEFAULT_PROFILE
TARGET_USER=""
USE_PTY=0

while [ $# -gt 0 ]; do
  case "$1" in
    enable|disable|status)
      [ -z "$ACTION" ] || die "action already set to '$ACTION'"
      ACTION=$1
      ;;
    --profile)
      shift
      [ $# -gt 0 ] || die "missing value for --profile"
      PROFILE=$1
      ;;
    --user)
      shift
      [ $# -gt 0 ] || die "missing value for --user"
      TARGET_USER=$1
      ;;
    --pty)
      USE_PTY=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument '$1'"
      ;;
  esac
  shift
done

[ -n "$ACTION" ] || {
  usage >&2
  exit 2
}

infer_target_user
validate_target_user
SUDOERS_FILE="${SUDOERS_DIR%/}/99-omp-passwordless-${TARGET_USER}"

if [ "$USE_PTY" -eq 1 ]; then
  if [ "$(id -u)" -eq 0 ]; then
    die "--pty is only needed when running without sudo"
  fi
  run_with_pty
  exit 0
fi

case "$ACTION" in
  enable)
    enable_passwordless
    ;;
  disable)
    disable_passwordless
    ;;
  status)
    show_status
    ;;
  *)
    die "unsupported action '$ACTION'"
    ;;
esac
