#!/bin/sh
set -eu

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

# --- Elevação de privilégios ---
if [ "$(id -u)" -ne 0 ]; then
  # Tenta usar sudo sem senha
  if sudo -n "$SCRIPT_DIR/$SCRIPT_NAME" "$@" 2>/dev/null; then
    exit 0
  fi
  
  # Se estiver rodando no terminal, pede a senha direto
  if [ -t 0 ] && [ -t 1 ]; then
    exec sudo "$SCRIPT_DIR/$SCRIPT_NAME" "$@"
  fi
  
  # Se for por atalho de desktop/background, pede um PTY gráfico
  for term in qterminal lxterminal xterm; do
    if command -v "$term" >/dev/null 2>&1; then
      exec "$term" -e sh -c "sudo \"$SCRIPT_DIR/$SCRIPT_NAME\" \"$@\"; code=\$?; printf '\nPressione Enter para fechar...'; read _; exit \$code"
    fi
  done
  
  printf "Erro: precisa de root e nenhum terminal foi encontrado para pedir a senha.\n" >&2
  exit 1
fi

# --- Valores padrão (Decision from iteration 9) ---
VAL_SWAPPINESS=80
VAL_PAGE_CLUSTER=3
VAL_ZSWAP=0
VAL_VFS_CACHE_PRESSURE=10
VAL_WATERMARK_SCALE_FACTOR=10
VAL_DIRTY_RATIO=5
VAL_DIRTY_BACKGROUND=2
VAL_MIN_FREE_KBYTES=67584

CONF_SWAPPINESS="/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf"
CONF_PAGE_CLUSTER="/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf"
CONF_VFS_CACHE="/etc/sysctl.d/99-lubuntu-optimize-vfs-cache.conf"
CONF_WATERMARK="/etc/sysctl.d/99-lubuntu-optimize-watermark.conf"
CONF_DIRTY="/etc/sysctl.d/99-lubuntu-optimize-dirty.conf"
CONF_MIN_FREE="/etc/sysctl.d/99-lubuntu-optimize-min-free.conf"
SYSCTL_BIN="/usr/sbin/sysctl"

# --- Lógica de Otimização ---
apply_tuning() {
  printf "Aplicando otimizações...\n"
  # 1. Swappiness
  printf " -> vm.swappiness = %s\n" "$VAL_SWAPPINESS"
  cat > "$CONF_SWAPPINESS" <<CONF
# Managed by $SCRIPT_NAME
vm.swappiness=$VAL_SWAPPINESS
CONF
  chmod 0644 "$CONF_SWAPPINESS"
  "$SYSCTL_BIN" -w "vm.swappiness=$VAL_SWAPPINESS" >/dev/null
  
  # 2. Page-cluster
  printf " -> vm.page-cluster = %s\n" "$VAL_PAGE_CLUSTER"
  cat > "$CONF_PAGE_CLUSTER" <<CONF
# Managed by $SCRIPT_NAME
vm.page-cluster=$VAL_PAGE_CLUSTER
CONF
  chmod 0644 "$CONF_PAGE_CLUSTER"
  "$SYSCTL_BIN" -w "vm.page-cluster=$VAL_PAGE_CLUSTER" >/dev/null


  # 3. VFS Cache Pressure
  printf " -> vm.vfs_cache_pressure = %s\n" "$VAL_VFS_CACHE_PRESSURE"
  cat > "$CONF_VFS_CACHE" <<CONF
# Managed by $SCRIPT_NAME
vm.vfs_cache_pressure=$VAL_VFS_CACHE_PRESSURE
CONF
  chmod 0644 "$CONF_VFS_CACHE"
  "$SYSCTL_BIN" -w "vm.vfs_cache_pressure=$VAL_VFS_CACHE_PRESSURE" >/dev/null

  # 4. Watermark Scale Factor
  printf " -> vm.watermark_scale_factor = %s\n" "$VAL_WATERMARK_SCALE_FACTOR"
  cat > "$CONF_WATERMARK" <<CONF
# Managed by $SCRIPT_NAME
vm.watermark_scale_factor=$VAL_WATERMARK_SCALE_FACTOR
CONF
  chmod 0644 "$CONF_WATERMARK"
  "$SYSCTL_BIN" -w "vm.watermark_scale_factor=$VAL_WATERMARK_SCALE_FACTOR" >/dev/null

  # 6. Dirty Ratios
  printf " -> vm.dirty_ratio = %s\n" "$VAL_DIRTY_RATIO"
  printf " -> vm.dirty_background_ratio = %s\n" "$VAL_DIRTY_BACKGROUND"
  cat > "$CONF_DIRTY" <<CONF
# Managed by $SCRIPT_NAME
vm.dirty_ratio=$VAL_DIRTY_RATIO
vm.dirty_background_ratio=$VAL_DIRTY_BACKGROUND
CONF
  chmod 0644 "$CONF_DIRTY"
  "$SYSCTL_BIN" -w "vm.dirty_ratio=$VAL_DIRTY_RATIO" >/dev/null
  "$SYSCTL_BIN" -w "vm.dirty_background_ratio=$VAL_DIRTY_BACKGROUND" >/dev/null

  # 7. Min Free Kbytes
  printf " -> vm.min_free_kbytes = %s\n" "$VAL_MIN_FREE_KBYTES"
  cat > "$CONF_MIN_FREE" <<CONF
# Managed by $SCRIPT_NAME
vm.min_free_kbytes=$VAL_MIN_FREE_KBYTES
CONF
  chmod 0644 "$CONF_MIN_FREE"
  "$SYSCTL_BIN" -w "vm.min_free_kbytes=$VAL_MIN_FREE_KBYTES" >/dev/null

  # 8. Zswap
  printf " -> zswap enabled = %s\n" "$VAL_ZSWAP"
  if [ -f /sys/module/zswap/parameters/enabled ]; then
    if [ "$VAL_ZSWAP" = "0" ]; then
      echo N > /sys/module/zswap/parameters/enabled
    else
      echo Y > /sys/module/zswap/parameters/enabled
    fi
  else
    printf "Aviso: /sys/module/zswap/parameters/enabled não encontrado.\n"
  fi
  
  printf "Otimização concluída com sucesso!\n"
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [apply]

Este script aplica as otimizações de memória (swappiness, page-cluster, zswap)
de forma persistente. Ele pede a senha do sudo via terminal gráfico caso
o passwordless sudo não esteja ativado.

Valores aplicados:
  - swappiness: $VAL_SWAPPINESS
  - page-cluster: $VAL_PAGE_CLUSTER
  - zswap: $VAL_ZSWAP
EOF
}

ACTION=${1:-apply}

case "$ACTION" in
  apply)
    apply_tuning
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac