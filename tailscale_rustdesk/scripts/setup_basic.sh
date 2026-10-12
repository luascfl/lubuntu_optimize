#!/usr/bin/env bash
set -euo pipefail

if [ "${CHECK_ONLY:-0}" != "1" ] && [ "${VALIDATE_ONLY:-0}" != "1" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo ./scripts/setup_basic.sh"
  exit 1
fi

RUSTDESK_VERSION="${RUSTDESK_VERSION:-}"
RUSTDESK_DEB="${RUSTDESK_DEB:-}"
CONFIGURE_XSET="${CONFIGURE_XSET:-0}"
LXQT_USER="${LXQT_USER:-}"
TMP_BASE="${TMP_BASE:-/var/tmp}"
DEBUG="${DEBUG:-0}"
CHECK_ONLY="${CHECK_ONLY:-0}"
PRECHECK="${PRECHECK:-1}"
FORCE_INSTALL="${FORCE_INSTALL:-0}"
SKIP_APT_UPDATE="${SKIP_APT_UPDATE:-0}"
STATUS_FULL="${STATUS_FULL:-0}"
DISABLE_TRAY="${DISABLE_TRAY:-1}"
TRAY_USER="${TRAY_USER:-}"
RUSTDESK_USER="${RUSTDESK_USER:-}"
VALIDATE="${VALIDATE:-1}"
VALIDATE_ONLY="${VALIDATE_ONLY:-0}"
LOGIND_VERIFY_DELAY="${LOGIND_VERIFY_DELAY:-180}"

report_rustdesk_status() {
  local full="${1:-0}"
  echo "RustDesk package:"
  if command -v dpkg >/dev/null 2>&1; then
    dpkg -l | awk '$1=="ii" && tolower($2)=="rustdesk"{print; found=1} END{if(!found) print "not installed"}'
  else
    echo "dpkg not available"
  fi

  echo "Desktop entry:"
  if [ -f /usr/share/applications/rustdesk.desktop ]; then
    dpkg -S /usr/share/applications/rustdesk.desktop 2>/dev/null || true
  else
    echo "not found"
  fi

  echo "Binary path:"
  command -v rustdesk || echo "not found"

  echo "Systemd service:"
  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-enabled rustdesk 2>/dev/null || echo "not enabled"
    systemctl is-active rustdesk 2>/dev/null || echo "inactive"
    if [ "$full" = "1" ]; then
      systemctl status rustdesk --no-pager -n 20 2>/dev/null || true
    fi
  else
    echo "systemctl not available"
  fi
}

resolve_target_user() {
  if [ -n "$RUSTDESK_USER" ]; then
    echo "$RUSTDESK_USER"
    return
  fi
  if [ -n "$TRAY_USER" ]; then
    echo "$TRAY_USER"
    return
  fi
  if [ -n "$LXQT_USER" ]; then
    echo "$LXQT_USER"
    return
  fi
  if [ -n "${SUDO_USER:-}" ]; then
    echo "$SUDO_USER"
    return
  fi
  echo ""
}

resolve_session_user() {
  if [ -n "$TRAY_USER" ]; then
    echo "$TRAY_USER"
    return
  fi
  if [ -n "$LXQT_USER" ]; then
    echo "$LXQT_USER"
    return
  fi
  if [ -n "${SUDO_USER:-}" ]; then
    echo "$SUDO_USER"
    return
  fi
  echo ""
}

resolve_user_home() {
  local user="$1"
  if [ -z "$user" ]; then
    return
  fi
  getent passwd "$user" | cut -d: -f6
}

set_ini_kv() {
  local file="$1"
  local key="$2"
  local value="$3"
  if [ -f "$file" ]; then
    sed -i "/^${key}=.*/d" "$file"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$file"
}

has_permanent_password() {
  local user
  user="$(resolve_target_user)"
  local home
  home="$(resolve_user_home "$user")"
  if [ -n "$home" ] && [ -f "$home/.config/rustdesk/RustDesk.toml" ]; then
    if grep -q '^password *= *' "$home/.config/rustdesk/RustDesk.toml"; then
      return 0
    fi
  fi
  return 1
}

validate_setup() {
  echo "Logind config:"
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze cat-config systemd/logind.conf | grep -E 'HandleLidSwitch|IdleAction' || true
  else
    grep -E 'HandleLidSwitch|IdleAction' /etc/systemd/logind.conf || true
  fi

  local user
  user="$(resolve_target_user)"
  local home
  home="$(resolve_user_home "$user")"

  echo "RustDesk config:"
  if [ -n "$home" ] && [ -d "$home/.config/rustdesk" ]; then
    if has_permanent_password; then
      echo "permanent password: present"
    else
      echo "permanent password: missing"
    fi
    if grep -q "verification-method *= *'use-permanent-password'" "$home/.config/rustdesk/RustDesk2.toml" 2>/dev/null; then
      echo "verification method: use-permanent-password"
    fi
  else
    echo "rustdesk config not found for user"
  fi

  echo "Tray override:"
  if [ -n "$home" ] && [ -f "$home/.config/autostart/rustdesk-no-tray.desktop" ]; then
    echo "present"
  else
    echo "missing"
  fi

  echo "Services:"
  for svc in rustdesk ssh tailscaled; do
    if command -v systemctl >/dev/null 2>&1; then
      local enabled="unknown"
      local active="unknown"
      if systemctl is-enabled --quiet "$svc"; then enabled="enabled"; else enabled="disabled"; fi
      if systemctl is-active --quiet "$svc"; then active="active"; else active="inactive"; fi
      echo "$svc: $enabled, $active"
    else
      echo "$svc: systemctl not available"
    fi
  done

  echo "Tailscale status:"
  if command -v tailscale >/dev/null 2>&1; then
    tailscale status 2>/dev/null | head -n 3 || true
    tailscale ip -4 2>/dev/null || true
  else
    echo "tailscale not available"
  fi

  echo "LXQt power config:"
  if [ -n "$home" ]; then
    local found=0
    for file in "$home/.config/lxqt/lxqt-powermanagement.conf" \
      "$home/.config/lxqt/powermanagement.conf"; do
      if [ -f "$file" ]; then
        echo "file: $file"
        grep -E 'lid|idle|idleness|blank|suspend' "$file" || true
        found=1
      fi
    done
    if [ "$found" -eq 0 ]; then
      echo "not found, verify in LXQt GUI"
    fi
  else
    echo "no user context for LXQt check"
  fi
}

if [ "$CHECK_ONLY" = "1" ]; then
  report_rustdesk_status "$STATUS_FULL"
  exit 0
fi

if [ "$DEBUG" = "1" ]; then
  set -x
fi

if [ "$PRECHECK" = "1" ]; then
  report_rustdesk_status "$STATUS_FULL"
fi

if [ "$VALIDATE_ONLY" = "1" ]; then
  validate_setup
  exit 0
fi

APT_UPDATED=0

apt_update_once() {
  if [ "$SKIP_APT_UPDATE" = "1" ]; then
    return
  fi
  if [ "$APT_UPDATED" = "1" ]; then
    return
  fi
  apt-get update
  APT_UPDATED=1
}

is_installed_pkg() {
  local pkg="$1"
  dpkg -s "$pkg" >/dev/null 2>&1
}

service_is_enabled() {
  systemctl is-enabled --quiet "$1"
}

service_is_active() {
  systemctl is-active --quiet "$1"
}

ensure_service() {
  local svc="$1"
  if service_is_enabled "$svc" && service_is_active "$svc"; then
    echo "$svc already enabled and active."
    return
  fi
  systemctl enable --now "$svc"
}

set_logind_kv() {
  local conf="/etc/systemd/logind.conf"
  local key="$1"
  local value="$2"
  if [ -f "$conf" ]; then
    sed -i "/^#\\?${key}=.*/d" "$conf"
  fi
  printf '\n%s=%s\n' "$key" "$value" >> "$conf"
}

backup_logind_conf() {
  local conf="/etc/systemd/logind.conf"
  local backup="/etc/systemd/logind.conf.bak"
  if [ -f "$conf" ] && [ ! -f "$backup" ]; then
    cp "$conf" "$backup"
  fi
}

configure_logind() {
  local conf="/etc/systemd/logind.conf"
  backup_logind_conf
  set_logind_kv HandleLidSwitch ignore
  set_logind_kv HandleLidSwitchExternalPower ignore
  set_logind_kv HandleLidSwitchDocked ignore
  set_logind_kv IdleAction ignore
  set_logind_kv IdleActionSec 0
  systemctl restart systemd-logind
}

write_logind_verify_script() {
  local path="/usr/local/bin/logind-verify"
  install -d -m 0755 /usr/local/bin
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

out_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
mkdir -p "$out_dir"
log="${out_dir}/logind-verify.log"

{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S %z') ==="
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze cat-config systemd/logind.conf | grep -E 'HandleLidSwitch|IdleAction' || true
  else
    grep -E 'HandleLidSwitch|IdleAction' /etc/systemd/logind.conf || true
  fi
} >> "$log"
EOF
  chmod 0755 "$path"
}

configure_logind_verify_autostart() {
  local user
  user="$(resolve_session_user)"
  if [ -z "$user" ]; then
    echo "No session user found for logind verify. Set TRAY_USER or LXQT_USER."
    return
  fi
  local home
  home="$(resolve_user_home "$user")"
  if [ -z "$home" ]; then
    echo "User not found for logind verify: $user"
    return
  fi
  write_logind_verify_script
  local dir="$home/.config/autostart"
  install -d -m 0755 "$dir"
  cat > "$dir/logind-verify.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Verify logind settings
Exec=sh -c "sleep ${LOGIND_VERIFY_DELAY}; /usr/local/bin/logind-verify"
X-GNOME-Autostart-enabled=true
EOF
  chown "$user":"$user" "$dir" "$dir/logind-verify.desktop"
}

ensure_lxqt_power_config() {
  local conf="$1"
  if [ ! -f "$conf" ]; then
    printf '[General]\n' > "$conf"
    return
  fi
  if ! grep -q '^[[]General[]]' "$conf"; then
    sed -i '1i[General]' "$conf"
  fi
}

configure_lxqt_powermanagement() {
  local user
  user="$(resolve_session_user)"
  if [ -z "$user" ]; then
    echo "No session user found for LXQt power config. Set TRAY_USER or LXQT_USER."
    return
  fi
  local home
  home="$(resolve_user_home "$user")"
  if [ -z "$home" ]; then
    echo "User not found for LXQt power config: $user"
    return
  fi
  local dir="$home/.config/lxqt"
  install -d -m 0755 "$dir"

  local conf
  for conf in "$dir/lxqt-powermanagement.conf" "$dir/powermanagement.conf"; do
    ensure_lxqt_power_config "$conf"
    set_ini_kv "$conf" "__userfile__" "true"
    set_ini_kv "$conf" "enableLidWatcher" "false"
    set_ini_kv "$conf" "enableExtMonLidClosedActions" "false"
    set_ini_kv "$conf" "enableIdlenessWatcher" "false"
    set_ini_kv "$conf" "lidClosedAction" "0"
    set_ini_kv "$conf" "lidClosedAcAction" "0"
    set_ini_kv "$conf" "lidClosedExtMonAction" "-1"
    set_ini_kv "$conf" "lidClosedExtMonAcAction" "-1"
    chown "$user":"$user" "$conf"
  done
}

resolve_rustdesk_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64) echo "x86_64" ;;
    arm64) echo "aarch64" ;;
    *) echo "$arch" ;;
  esac
}

resolve_rustdesk_version() {
  if [ -n "$RUSTDESK_VERSION" ]; then
    return
  fi
  local json
  json="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest)"
  local tag
  tag="$(printf '%s\n' "$json" | awk -F'"' '/"tag_name"/{print $4; exit}')"
  if [ -z "$tag" ]; then
    echo "Failed to resolve RustDesk version. Set RUSTDESK_VERSION explicitly."
    exit 1
  fi
  RUSTDESK_VERSION="${tag#v}"
}

install_rustdesk() {
  if command -v dpkg >/dev/null 2>&1; then
    if dpkg -l | awk '$1=="ii" && tolower($2)=="rustdesk"{found=1} END{exit(!found)}'; then
      ensure_service rustdesk
      return
    fi
  fi
  if [ -n "$RUSTDESK_DEB" ]; then
    if [ ! -f "$RUSTDESK_DEB" ]; then
      echo "RUSTDESK_DEB not found: $RUSTDESK_DEB"
      exit 1
    fi
    apt-get install -y "$RUSTDESK_DEB"
    ensure_service rustdesk
    return
  fi
  resolve_rustdesk_version
  local arch
  arch="$(resolve_rustdesk_arch)"
  local deb="rustdesk-${RUSTDESK_VERSION}-${arch}.deb"
  local url="https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/${deb}"
  local tmp_base="$TMP_BASE"
  if [ ! -d "$tmp_base" ] || [ ! -w "$tmp_base" ]; then
    tmp_base="/tmp"
  fi
  local tmpdir
  tmpdir="$(mktemp -d -p "$tmp_base")"
  trap 'rm -rf "$tmpdir"' RETURN
  local tmp_deb="${tmpdir}/${deb}"
  ulimit -f unlimited 2>/dev/null || true
  if ! touch "$tmpdir/.write_test"; then
    echo "Cannot write to $tmpdir"
    exit 1
  fi
  rm -f "$tmpdir/.write_test"
  echo "Downloading RustDesk to $tmp_deb"
  if ! curl -fL --retry 3 --retry-delay 2 "$url" -o "$tmp_deb"; then
    if command -v wget >/dev/null 2>&1; then
      wget -O "$tmp_deb" "$url"
    else
      echo "curl failed and wget is not available"
      exit 1
    fi
  fi
  apt-get install -y "$tmp_deb"
  ensure_service rustdesk
}

install_ssh() {
  if [ "$FORCE_INSTALL" != "1" ] && is_installed_pkg openssh-server; then
    ensure_service ssh
    return
  fi
  apt_update_once
  apt-get install -y openssh-server
  ensure_service ssh
}

install_tailscale() {
  if [ "$FORCE_INSTALL" != "1" ] && is_installed_pkg tailscale; then
    ensure_service tailscaled
    return
  fi
  curl -fsSL https://tailscale.com/install.sh | sh
  ensure_service tailscaled
}

install_tmux() {
  if [ "$FORCE_INSTALL" != "1" ] && is_installed_pkg tmux; then
    echo "tmux already installed."
    return
  fi
  apt_update_once
  apt-get install -y tmux
}

install_xvfb() {
  if [ "$FORCE_INSTALL" != "1" ] && is_installed_pkg xvfb; then
    echo "xvfb already installed."
    return
  fi
  apt_update_once
  apt-get install -y xvfb
}

write_rustdesk_dropins() {
  local user
  user="$(resolve_target_user)"
  if [ -z "$user" ]; then
    echo "No target user found for RustDesk. Set RUSTDESK_USER=<user> or TRAY_USER."
    return
  fi

  local uid
  uid="$(id -u "$user")"
  local dir="/etc/systemd/system/rustdesk.service.d"
  install -d -m 0755 "$dir"

  cat > "$dir/90-xvfb.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/xvfb-run -a /usr/bin/rustdesk --service
EOF

  cat > "$dir/95-user.conf" <<EOF
[Service]
User=${user}
Group=${user}
Environment=XDG_RUNTIME_DIR=/run/user/${uid}
EOF

  cat > "$dir/99-headless.conf" <<'EOF'
[Service]
Environment=DISPLAY=
Environment=XAUTHORITY=
EOF
}

configure_xset_autostart() {
  if [ "$CONFIGURE_XSET" != "1" ]; then
    return
  fi
  if [ -z "$LXQT_USER" ]; then
    echo "CONFIGURE_XSET=1 requires LXQT_USER to be set"
    exit 1
  fi
  local home
  home="$(getent passwd "$LXQT_USER" | cut -d: -f6)"
  if [ -z "$home" ]; then
    echo "User not found: $LXQT_USER"
    exit 1
  fi
  local dir="$home/.config/autostart"
  install -d -m 0755 "$dir"
  cat > "$dir/always-on-xset.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Disable screen blanking
Exec=sh -c "xset s off -dpms && xset s noblank"
X-GNOME-Autostart-enabled=true
EOF
  chown "$LXQT_USER":"$LXQT_USER" "$dir" "$dir/always-on-xset.desktop"
}

configure_rustdesk_tray() {
  if [ "$DISABLE_TRAY" != "1" ]; then
    return
  fi
  if [ -z "$TRAY_USER" ]; then
    if [ -n "$LXQT_USER" ]; then
      TRAY_USER="$LXQT_USER"
    elif [ -n "${SUDO_USER:-}" ]; then
      TRAY_USER="$SUDO_USER"
    fi
  fi
  if [ -z "$TRAY_USER" ]; then
    echo "DISABLE_TRAY=1 but no TRAY_USER found. Set TRAY_USER=<user> to proceed."
    return
  fi
  local home
  home="$(getent passwd "$TRAY_USER" | cut -d: -f6)"
  if [ -z "$home" ]; then
    echo "User not found for tray config: $TRAY_USER"
    return
  fi
  local dir="$home/.config/autostart"
  install -d -m 0755 "$dir"
  cat > "$dir/rustdesk-no-tray.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hide RustDesk tray
Exec=sh -c "pkill -f 'rustdesk --tray' || true"
X-GNOME-Autostart-enabled=true
EOF
  chown "$TRAY_USER":"$TRAY_USER" "$dir" "$dir/rustdesk-no-tray.desktop"
  pkill -u "$TRAY_USER" -f "rustdesk --tray" || true
}

configure_logind
configure_lxqt_powermanagement
configure_xset_autostart
configure_rustdesk_tray
configure_logind_verify_autostart

install_ssh
install_tailscale
install_tmux
install_xvfb
install_rustdesk
write_rustdesk_dropins
systemctl daemon-reload
ensure_service rustdesk

if [ "$VALIDATE" = "1" ]; then
  validate_setup
fi

next_steps=()
if command -v tailscale >/dev/null 2>&1; then
  if ! tailscale status >/dev/null 2>&1; then
    next_steps+=("- Run: sudo tailscale up")
  fi
fi
if command -v rustdesk >/dev/null 2>&1; then
  if ! has_permanent_password; then
    next_steps+=("- Set a permanent password in RustDesk UI")
  fi
fi

if [ "${#next_steps[@]}" -gt 0 ]; then
  echo "Next steps:"
  printf '%s\n' "${next_steps[@]}"
fi
