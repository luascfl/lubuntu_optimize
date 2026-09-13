#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-setup}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$SCRIPT_DIR/backups/$TIMESTAMP"

# Resolve home do usuário alvo (evita apontar para /root quando rodar com sudo).
if [[ -n "${TARGET_HOME:-}" ]]; then
  EFFECTIVE_HOME="$TARGET_HOME"
elif [[ -n "${SUDO_USER:-}" ]] && getent passwd "$SUDO_USER" >/dev/null 2>&1; then
  EFFECTIVE_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
elif [[ "$HOME" == "/root" && -d "/home/lucas" ]]; then
  EFFECTIVE_HOME="/home/lucas"
else
  EFFECTIVE_HOME="$HOME"
fi

TMUX_CONF="${TMUX_CONF:-$EFFECTIVE_HOME/.tmux.conf}"
BASHRC="${BASHRC:-$EFFECTIVE_HOME/.bashrc}"
QTERM_INI="${QTERM_INI:-$EFFECTIVE_HOME/.config/qterminal.org/qterminal.ini}"
OMP_DIR="${OMP_DIR:-$EFFECTIVE_HOME/.omp}"
OMP_KEYBINDINGS="${OMP_KEYBINDINGS:-$OMP_DIR/agent/keybindings.json}"
ICEWM_KEYS="${ICEWM_KEYS:-$EFFECTIVE_HOME/.icewm/keys}"
PCMANFM_DEFAULT_CONF="${PCMANFM_DEFAULT_CONF:-$EFFECTIVE_HOME/.config/pcmanfm-qt/default/settings.conf}"
PCMANFM_LXQT_CONF="${PCMANFM_LXQT_CONF:-$EFFECTIVE_HOME/.config/pcmanfm-qt/lxqt/settings.conf}"
PCMANFM_QTERMINAL_WRAPPER="${PCMANFM_QTERMINAL_WRAPPER:-$EFFECTIVE_HOME/.local/bin/pcmanfm-qterminal-here}"
PCMANFM_TMUX_LAUNCHER="${PCMANFM_TMUX_LAUNCHER:-$EFFECTIVE_HOME/.local/bin/pcmanfm-tmux-session}"
PCMANFM_TERMINAL_COMMAND="${PCMANFM_TERMINAL_COMMAND:-$PCMANFM_QTERMINAL_WRAPPER}"

SHORTCUT_KEYS=(
  'Add%20Tab'
  'Close%20Tab'
  'New%20Window'
  'Next%20Tab'
  'Previous%20Tab'
  'Move%20Tab%20Left'
  'Move%20Tab%20Right'
  'Rename%20Session'
  'Left%20Subterminal'
  'Right%20Subterminal'
  'Top%20Subterminal'
  'Bottom%20Subterminal'
)

log() {
  printf '[tmux-setup] %s\n' "$*"
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$file" "$BACKUP_DIR/$(basename "$file").bak"
    log "backup: $BACKUP_DIR/$(basename "$file").bak"
  fi
}

backup_omp_profile_keybindings() {
  local agent_dir profile_path
  shopt -s nullglob
  for agent_dir in "$OMP_DIR"/profiles/*/agent; do
    [[ -d "$agent_dir" ]] || continue
    profile_path="$agent_dir/$(basename "$OMP_KEYBINDINGS")"
    backup_file "$profile_path"
  done
  shopt -u nullglob
}

ensure_omp_profile_keybindings_writable() {
  local agent_dir profile_path
  shopt -s nullglob
  for agent_dir in "$OMP_DIR"/profiles/*/agent; do
    [[ -d "$agent_dir" ]] || continue
    profile_path="$agent_dir/$(basename "$OMP_KEYBINDINGS")"
    ensure_writable_path "$profile_path" || {
      shopt -u nullglob
      return 1
    }
  done
  shopt -u nullglob
}

ensure_writable_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    if [[ ! -w "$path" ]]; then
      log "ERRO: sem permissão de escrita em $path"
      log 'Dica: ajuste o owner/permissões do arquivo e rode o setup novamente.'
      return 1
    fi
    return 0
  fi

  local parent
  parent="$(dirname "$path")"
  if [[ ! -d "$parent" ]]; then
    mkdir -p "$parent" 2>/dev/null || true
  fi
  if [[ ! -w "$parent" ]]; then
    log "ERRO: sem permissão para criar $path em $parent"
    return 1
  fi
}

install_tmux_plugins() {
  local installer=""
  if [[ -x /usr/share/tmux-plugin-manager/bin/install_plugins ]]; then
    installer="/usr/share/tmux-plugin-manager/bin/install_plugins"
  elif [[ -x "$EFFECTIVE_HOME/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    installer="$EFFECTIVE_HOME/.tmux/plugins/tpm/bin/install_plugins"
  fi

  if [[ -z "$installer" ]]; then
    log 'ERRO: instalador do TPM não encontrado.'
    return 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    log 'ERRO: git não encontrado no PATH, necessário para baixar plugins.'
    return 1
  fi

  log "instalando plugins do tmux via TPM: $installer"
  if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    sudo -u "$SUDO_USER" -H env HOME="$EFFECTIVE_HOME" tmux start-server \; set-environment -g TMUX_PLUGIN_MANAGER_PATH "$EFFECTIVE_HOME/.tmux/plugins/"
    sudo -u "$SUDO_USER" -H env HOME="$EFFECTIVE_HOME" "$installer"
  else
    tmux start-server \; set-environment -g TMUX_PLUGIN_MANAGER_PATH "$EFFECTIVE_HOME/.tmux/plugins/"
    env HOME="$EFFECTIVE_HOME" "$installer"
  fi
}

apply_setup() {
  log 'aplicando configuração...'
  log "home alvo: $EFFECTIVE_HOME"
  log "tmux conf: $TMUX_CONF"
  log "bashrc: $BASHRC"
  log "qterminal ini: $QTERM_INI"
  log "omp keybindings: $OMP_KEYBINDINGS"

  local restart_pcmanfm=0
  if command -v pcmanfm-qt >/dev/null 2>&1 && pgrep -x pcmanfm-qt >/dev/null 2>&1; then
    restart_pcmanfm=1
    log 'parando PCManFM-Qt para evitar sobrescrita das preferências...'
    if command -v timeout >/dev/null 2>&1; then
      timeout 5s pcmanfm-qt --quit >/dev/null 2>&1 || true
    else
      pcmanfm-qt --quit >/dev/null 2>&1 || true
    fi
    sleep 1
  fi
  log "icewm keys: $ICEWM_KEYS"
  log "pcmanfm default conf: $PCMANFM_DEFAULT_CONF"
  log "pcmanfm lxqt conf: $PCMANFM_LXQT_CONF"
  log "pcmanfm qterminal wrapper: $PCMANFM_QTERMINAL_WRAPPER"
  log "pcmanfm tmux launcher: $PCMANFM_TMUX_LAUNCHER"

  backup_file "$TMUX_CONF"
  backup_file "$BASHRC"
  backup_file "$QTERM_INI"
  backup_file "$OMP_KEYBINDINGS"
  backup_omp_profile_keybindings
  backup_file "$ICEWM_KEYS"
  backup_file "$PCMANFM_DEFAULT_CONF"
  backup_file "$PCMANFM_LXQT_CONF"
  backup_file "$PCMANFM_QTERMINAL_WRAPPER"
  backup_file "$PCMANFM_TMUX_LAUNCHER"
  ensure_writable_path "$TMUX_CONF" || return 1
  ensure_writable_path "$BASHRC" || return 1
  ensure_writable_path "$QTERM_INI" || return 1
  ensure_writable_path "$OMP_KEYBINDINGS" || return 1
  ensure_omp_profile_keybindings_writable || return 1
  ensure_writable_path "$ICEWM_KEYS" || return 1
  ensure_writable_path "$PCMANFM_DEFAULT_CONF" || return 1
  ensure_writable_path "$PCMANFM_LXQT_CONF" || return 1
  ensure_writable_path "$PCMANFM_QTERMINAL_WRAPPER" || return 1
  ensure_writable_path "$PCMANFM_TMUX_LAUNCHER" || return 1


  python3 - "$TMUX_CONF" "$BASHRC" "$QTERM_INI" "$OMP_KEYBINDINGS" "$OMP_DIR" "$ICEWM_KEYS" "$PCMANFM_DEFAULT_CONF" "$PCMANFM_LXQT_CONF" "$PCMANFM_QTERMINAL_WRAPPER" "$PCMANFM_TMUX_LAUNCHER" "$PCMANFM_TERMINAL_COMMAND" <<'PY'
from pathlib import Path
import json
import shlex
import re
import sys

TMUX_CONF = Path(sys.argv[1])
BASHRC = Path(sys.argv[2])
QTERM_INI = Path(sys.argv[3])
OMP_KEYBINDINGS = Path(sys.argv[4])
OMP_DIR = Path(sys.argv[5])
ICEWM_KEYS = Path(sys.argv[6])
PCMANFM_DEFAULT_CONF = Path(sys.argv[7])
PCMANFM_LXQT_CONF = Path(sys.argv[8])
PCMANFM_QTERMINAL_WRAPPER = Path(sys.argv[9])
PCMANFM_TMUX_LAUNCHER = Path(sys.argv[10])
PCMANFM_TERMINAL_COMMAND = sys.argv[11]

def read_text(path: Path) -> str:
    return path.read_text(encoding='utf-8') if path.exists() else ''

def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')

def upsert_block(path: Path, start: str, end: str, content: str) -> None:
    text = read_text(path)
    block = f"{start}\n{content.rstrip()}\n{end}"
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
    if pattern.search(text):
        updated = pattern.sub(block, text, count=1)
    else:
        updated = (text.rstrip() + "\n\n" + block + "\n") if text.strip() else (block + "\n")
    write_text(path, updated)

def write_executable(path: Path, text: str) -> None:
    write_text(path, text)
    path.chmod(0o755)

def set_ini_value(path: Path, section: str, key: str, value: str) -> None:
    lines = read_text(path).splitlines()
    header = f'[{section}]'
    entry = f'{key}={value}'
    updated = []
    in_section = False
    section_seen = False
    key_set = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('[') and stripped.endswith(']'):
            if in_section and not key_set:
                updated.append(entry)
                key_set = True
            in_section = stripped == header
            section_seen = section_seen or in_section
            updated.append(line)
            continue

        if in_section and line.startswith(key + '='):
            if not key_set:
                updated.append(entry)
                key_set = True
            continue

        updated.append(line)

    if not section_seen:
        if updated and updated[-1] != '':
            updated.append('')
        updated.extend([header, entry])
    elif in_section and not key_set:
        updated.append(entry)

    write_text(path, '\n'.join(updated).rstrip() + '\n')

def upsert_icewm_qterminal_shortcut(path: Path) -> None:
    target = 'key "Ctrl+Alt+t" qterminal'
    pattern = re.compile(r'^\s*key\s+"(?:Ctrl\+Alt\+[tT]|Control\+Alt\+[tT]|Alt\+Ctrl\+[tT]|Alt\+Control\+[tT])"\s+')
    lines = read_text(path).splitlines()
    updated = []
    inserted = False

    for line in lines:
        if pattern.match(line):
            if not inserted:
                updated.append(target)
                inserted = True
            continue
        updated.append(line)

    if not inserted:
        if updated and updated[-1] != '':
            updated.append('')
        updated.extend(['# Terminal', target])

    write_text(path, '\n'.join(updated).rstrip() + '\n')

tmux_content = r'''# Configuração gerenciada para usar tmux com atalhos próximos do QTerminal.
set -g extended-keys on
set -as terminal-features ',xterm*:extkeys'
set -s extended-keys-format csi-u
set -s backspace C-?
# Workaround para crash intermitente de Bun em CPU sem AVX no omp
set-environment -g BUN_JSC_useJIT 0
# Normaliza Backspace para DEL (0x7f) no tmux, evitando variações C-h/CSI-u em apps TUI
bind -n BSpace send-keys C-?
bind -n C-h send-keys C-?

set -g mouse on
set -g history-limit 100000
set -g renumber-windows on
set -g base-index 1
setw -g pane-base-index 1
set -g set-clipboard on

# Menu de contexto do tmux em clique direito (e também botão do meio, para funcionar com swap do QTerminal)
bind -T root MouseDown2Pane display-menu -T "Pane #{pane_index}" -x M -y M "Copiar modo" c { copy-mode -t= } "Colar buffer" v { paste-buffer -p } "" "" "Split vertical" h { split-window -h -c "#{pane_current_path}" } "Split horizontal" s { split-window -v -c "#{pane_current_path}" } "" "" "Fechar pane" x { kill-pane }
bind -T root MouseDown3Pane display-menu -T "Pane #{pane_index}" -x M -y M "Copiar modo" c { copy-mode -t= } "Colar buffer" v { paste-buffer -p } "" "" "Split vertical" h { split-window -h -c "#{pane_current_path}" } "Split horizontal" s { split-window -v -c "#{pane_current_path}" } "" "" "Fechar pane" x { kill-pane }
bind -T root MouseDown3Status display-menu -T "Janela #{window_index}:#{window_name}" -x W -y W "Nova aba" n { new-window -c "#{pane_current_path}" } "Renomear aba" r { command-prompt -I "#W" { rename-window "%%" } } "Fechar aba" x { kill-window }

# Abas (windows)
bind -n M-t new-window -c '#{pane_current_path}'
bind -n C-S-W confirm-before -p 'Fechar aba #W? (y/n)' kill-window
bind -n M-w confirm-before -p 'Fechar aba #W? (y/n)' kill-window
unbind -n C-S-T
unbind -n C-t

bind -n C-PageDown next-window
bind -n C-PageUp previous-window
bind -n C-S-PageDown swap-window -t +1 \; next-window
bind -n C-S-PageUp swap-window -t -1 \; previous-window
bind -n M-S-Right swap-window -t +1 \; next-window
bind -n M-S-Left swap-window -t -1 \; previous-window
unbind -n M-S-s
bind -n M-r command-prompt -I '#{window_name}' "rename-window '%%'"

# Subterminais (panes)
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
unbind -n M-Up
unbind -n M-Down
bind -n M-S-Enter split-window -v -c '#{pane_current_path}'
bind -n M-Enter split-window -h -c '#{pane_current_path}'

# Copiar e colar
setw -g mode-keys vi
# Roda do mouse mais lenta no histórico do tmux (3 linhas por passo)
bind -T copy-mode-vi WheelUpPane select-pane \; send-keys -X -N 3 scroll-up
bind -T copy-mode-vi WheelDownPane select-pane \; send-keys -X -N 3 scroll-down
bind -T copy-mode WheelUpPane select-pane \; send-keys -X -N 3 scroll-up
bind -T copy-mode WheelDownPane select-pane \; send-keys -X -N 3 scroll-down
bind -T copy-mode-vi v send-keys -X begin-selection
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -T copy-mode y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -T copy-mode Enter send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null"
bind -n C-S-V run-shell 'tmux set-buffer -- "$(xclip -o -selection clipboard 2>/dev/null || wl-paste -n 2>/dev/null)"; tmux paste-buffer'
bind -n S-Insert run-shell 'tmux set-buffer -- "$(xclip -o -selection clipboard 2>/dev/null || wl-paste -n 2>/dev/null)"; tmux paste-buffer'

# Toggle rápido do mouse
bind -n M-m if-shell -F '#{mouse}' 'set -g mouse off; display-message "Mouse: OFF"' 'set -g mouse on; display-message "Mouse: ON"'

# tmux plugins: resurrect + continuum
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-save-shell-history 'on'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'

# Carrega TPM (pacote APT ou fallback no diretório padrão)
if-shell '[ -x /usr/share/tmux-plugin-manager/tpm ]' "run '/usr/share/tmux-plugin-manager/tpm'" "run '~/.tmux/plugins/tpm/tpm'" '''

bashrc_content = r'''# Inicia/retoma a sessão tmux "main" automaticamente quando abrir no QTerminal.
# Quando o QTerminal abre em uma pasta específica, cria uma nova window do tmux nessa pasta.
if command -v tmux >/dev/null 2>&1 && [ -z "${TMUX:-}" ] && [ -z "${SSH_TTY:-}" ]; then
    __qterm_parent="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '[:space:]')"
    if [ "${__qterm_parent}" = "qterminal" ]; then
        if tmux has-session -t main 2>/dev/null; then
            __qterm_target="$(tmux new-window -P -F '#{session_name}:#{window_index}' -t main -c "$PWD")"
            exec tmux attach-session -t "$__qterm_target"
        else
            exec tmux new-session -s main -c "$PWD"
        fi
    fi
    unset __qterm_parent __qterm_target
fi'''

pcmanfm_qterminal_wrapper = f'''#!/bin/sh
# Open QTerminal from PCManFM-Qt in the folder PCManFM provided as cwd.
# The explicit --workdir avoids QTerminal falling back to an existing window's directory.
dir=${{PWD:-$HOME}}

export PCMANFM_QTERMINAL_DIR="$dir"
exec /usr/bin/qterminal --workdir "$dir" -e {shlex.quote(str(PCMANFM_TMUX_LAUNCHER))}
'''

pcmanfm_tmux_launcher = '''#!/bin/sh
# Runs inside QTerminal. PCManFM's wrapper sets PCMANFM_QTERMINAL_DIR.
# Always uses the main tmux session so tmux-resurrect/continuum apply to these windows.
dir=${PCMANFM_QTERMINAL_DIR:-${PWD:-$HOME}}
session=main

if command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t "$session" 2>/dev/null; then
        target=$(tmux new-window -P -F '#{session_name}:#{window_index}' -t "$session" -c "$dir")
        exec tmux attach-session -t "$target"
    fi
    exec tmux new-session -s "$session" -c "$dir"
fi

cd "$dir" 2>/dev/null || cd "$HOME" || exit 1
exec /bin/bash -l
'''

upsert_block(
    TMUX_CONF,
    '# >>> qterminal tmux setup >>>',
    '# <<< qterminal tmux setup <<<',
    tmux_content,
)

upsert_block(
    BASHRC,
    '# >>> qterminal tmux autostart >>>',
    '# <<< qterminal tmux autostart <<<',
    bashrc_content,
)

upsert_icewm_qterminal_shortcut(ICEWM_KEYS)
for pcmanfm_conf in (PCMANFM_DEFAULT_CONF, PCMANFM_LXQT_CONF):
    set_ini_value(pcmanfm_conf, 'System', 'Terminal', PCMANFM_TERMINAL_COMMAND)
write_executable(PCMANFM_QTERMINAL_WRAPPER, pcmanfm_qterminal_wrapper)
write_executable(PCMANFM_TMUX_LAUNCHER, pcmanfm_tmux_launcher)

if QTERM_INI.exists():
    keys = [
        'Add%20Tab',
        'Close%20Tab',
        'New%20Window',
        'Next%20Tab',
        'Previous%20Tab',
        'Move%20Tab%20Left',
        'Move%20Tab%20Right',
        'Rename%20Session',
        'Left%20Subterminal',
        'Right%20Subterminal',
        'Top%20Subterminal',
        'Bottom%20Subterminal',
    ]
    lines = QTERM_INI.read_text(encoding='utf-8').splitlines()
    updated = []
    swap_key = 'SwapMouseButtons2and3'
    swap_set = False
    in_general = False
    general_seen = False
    for line in lines:
        stripped = line.strip()
        if stripped == '[General]':
            in_general = True
            general_seen = True
            updated.append(line)
            continue
        if stripped.startswith('[') and stripped.endswith(']') and stripped != '[General]':
            if in_general and not swap_set:
                updated.append(swap_key + '=true')
                swap_set = True
            in_general = False

        replaced = False
        for key in keys:
            if line.startswith(key + '='):
                updated.append(key + '=')
                replaced = True
                break
        if not replaced and line.startswith(swap_key + '='):
            updated.append(swap_key + '=true')
            swap_set = True
            replaced = True
        if not replaced:
            updated.append(line)

    if in_general and not swap_set:
        updated.append(swap_key + '=true')
        swap_set = True

    if not general_seen:
        updated = ['[General]', swap_key + '=true', ''] + updated
    elif not swap_set:
        # Fallback de segurança, caso o parser não encontre a seção corretamente.
        updated.append(swap_key + '=true')

    QTERM_INI.write_text('\n'.join(updated) + '\n', encoding='utf-8')

def normalize_keys(value):
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, str) and item]
    return []

def ensure_required_keys(config: dict, action: str, required: list[str]) -> bool:
    existing = normalize_keys(config.get(action))
    merged = existing[:]
    for key in required:
        if key not in merged:
            merged.append(key)
    if action not in config or merged != existing:
        config[action] = merged
        return True
    return False

def profile_keybinding_paths(default_path: Path, omp_dir: Path) -> list[Path]:
    paths = [default_path]
    profiles_dir = omp_dir / 'profiles'
    if profiles_dir.exists():
        for agent_dir in sorted(profiles_dir.glob('*/agent')):
            if agent_dir.is_dir():
                paths.append(agent_dir / default_path.name)
    return paths

kb_config: dict = {}
kb_paths = profile_keybinding_paths(OMP_KEYBINDINGS, OMP_DIR)

for index, keybinding_path in enumerate(kb_paths):
    local_config: dict = {}
    if keybinding_path.exists():
        try:
            loaded = json.loads(keybinding_path.read_text(encoding='utf-8'))
            if isinstance(loaded, dict):
                local_config = loaded
        except Exception:
            local_config = {}
    elif index != 0:
        local_config = json.loads(json.dumps(kb_config))

    local_changed = False
    local_changed = ensure_required_keys(
        local_config,
        'tui.editor.deleteCharBackward',
        ['backspace', 'ctrl+h', 'ctrl+?'],
    ) or local_changed
    local_changed = ensure_required_keys(
        local_config,
        'tui.editor.deleteWordBackward',
        ['ctrl+w', 'alt+backspace', 'ctrl+backspace'],
    ) or local_changed

    if local_changed or not keybinding_path.exists():
        keybinding_path.parent.mkdir(parents=True, exist_ok=True)
        keybinding_path.write_text(json.dumps(local_config, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    if index == 0:
        kb_config = local_config

print('ok: arquivos configurados')
PY

  if [[ "$restart_pcmanfm" -eq 1 ]] && command -v pcmanfm-qt >/dev/null 2>&1; then
    log 'reiniciando PCManFM-Qt...'
    pcmanfm-qt -d >/dev/null 2>&1 &
  fi

  install_tmux_plugins
  log 'configuração aplicada.'
}

verify_setup() {
  log 'verificando configuração...'
  log "home alvo: $EFFECTIVE_HOME"
  local issues=0

  if [[ ! -f "$TMUX_CONF" ]]; then
    log "ERRO: $TMUX_CONF não existe"
    issues=$((issues + 1))
  fi

  if command -v tmux >/dev/null 2>&1; then
    local sock="qterm_setup_check_$$"
    if tmux -f "$TMUX_CONF" -L "$sock" new-session -d -s __check >/dev/null 2>&1; then
      local keys_root
      local keys_vi
      local server_opts
      local server_env
      keys_root="$(tmux -L "$sock" list-keys -T root || true)"
      keys_vi="$(tmux -L "$sock" list-keys -T copy-mode-vi || true)"
      server_opts="$(tmux -L "$sock" show-options -s || true)"
      server_env="$(tmux -L "$sock" show-environment -g || true)"
      tmux -L "$sock" kill-server >/dev/null 2>&1 || true

      for pattern in 'M-t' 'M-r' 'C-S-W' 'M-w' 'C-NPage' 'C-PPage' 'M-m' 'C-S-V'; do
        if printf '%s\n' "$keys_root" | grep -q "$pattern"; then
          log "OK tmux key: $pattern"
        else
          log "ERRO tmux key ausente: $pattern"
          issues=$((issues + 1))
        fi
      done

      if printf '%s\n' "$keys_root" | grep -q 'C-S-T'; then
        log 'ERRO tmux key: C-S-T ainda está capturado (conflito com Codex/Gemini)'
        issues=$((issues + 1))
      else
        log 'OK tmux key: C-S-T livre para Codex/Gemini'
      fi

      if printf '%s\n' "$keys_root" | grep -q 'C-t'; then
        log 'ERRO tmux key: C-t ainda está capturado (conflito com Codex/Gemini)'
        issues=$((issues + 1))
      else
        log 'OK tmux key: C-t livre para Codex/Gemini'
      fi

      if printf '%s\n' "$keys_root" | grep -qE 'M-Up|M-Down'; then
        log 'ERRO tmux key: Alt+Up/Alt+Down ainda capturados (conflito com Codex/Gemini)'
        issues=$((issues + 1))
      else
        log 'OK tmux key: Alt+Up/Alt+Down livres para Codex/Gemini'
      fi

      if printf '%s\n' "$keys_root" | grep -qE 'S-Insert|S-IC'; then
        log 'OK tmux key: Shift+Insert'
      else
        log 'ERRO tmux key ausente: Shift+Insert'
        issues=$((issues + 1))
      fi
      if printf '%s\n' "$server_opts" | grep -q '^extended-keys-format csi-u$'; then
        log 'OK tmux: extended-keys-format csi-u'
      else
        log 'ERRO tmux: extended-keys-format não está csi-u'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$server_opts" | grep -Fq 'backspace C-?'; then
        log 'OK tmux: backspace C-?'
      else
        log 'ERRO tmux: backspace não está C-?'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$keys_root" | grep -qE 'BSpace.*send-keys C-\?|BSpace.*send C-\?'; then
        log 'OK tmux: BSpace normalizado para C-?'
      else
        log 'ERRO tmux: BSpace não está normalizado para C-?'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$keys_root" | grep -qE 'C-h.*send-keys C-\?|C-h.*send C-\?'; then
        log 'OK tmux: C-h normalizado para C-?'
      else
        log 'ERRO tmux: C-h não está normalizado para C-?'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$server_env" | grep -q '^BUN_JSC_useJIT=0$'; then
        log 'OK tmux env: BUN_JSC_useJIT=0'
      else
        log 'ERRO tmux env: BUN_JSC_useJIT não está 0'
        issues=$((issues + 1))
      fi


      if printf '%s\n' "$keys_vi" | grep -q 'WheelUpPane.*-N 3 scroll-up' && \
         printf '%s\n' "$keys_vi" | grep -q 'WheelDownPane.*-N 3 scroll-down'; then
        log 'OK tmux: rolagem do mouse ajustada para 3 linhas'
      else
        log 'ERRO tmux: rolagem do mouse não está em 3 linhas'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$keys_root" | grep -q 'MouseDown2Pane.*display-menu'; then
        log 'OK tmux: clique direito (via swap) abre menu de contexto'
      else
        log 'ERRO tmux: MouseDown2Pane não está abrindo menu'
        issues=$((issues + 1))
      fi

      if printf '%s\n' "$keys_root" | grep -qE 'MouseDown3Pane|MouseDown3Status|MouseDown3StatusLeft'; then
        log 'OK tmux: menu de contexto do botão direito ativo'
      else
        log 'ERRO tmux: menu de contexto do botão direito ausente'
        issues=$((issues + 1))
      fi
    else
      log 'ERRO: tmux não conseguiu carregar o arquivo de configuração.'
      issues=$((issues + 1))
    fi
  else
    log 'ERRO: tmux não encontrado no PATH.'
    issues=$((issues + 1))
  fi

  if grep -q '^# >>> qterminal tmux autostart >>>' "$BASHRC" 2>/dev/null && \
     grep -q '^# <<< qterminal tmux autostart <<<' "$BASHRC" 2>/dev/null; then
    log 'OK bashrc: bloco de autostart presente'
  else
    log 'ERRO bashrc: bloco de autostart ausente'
    issues=$((issues + 1))
  fi

  if grep -Fq 'tmux new-window -P -F' "$BASHRC" 2>/dev/null && \
     grep -Fq -- '-c "$PWD"' "$BASHRC" 2>/dev/null; then
    log 'OK bashrc: QTerminal abre nova window tmux no diretório atual'
  else
    log 'ERRO bashrc: autostart do QTerminal não cria window tmux no diretório atual'
    issues=$((issues + 1))
  fi

  if command -v qterminal >/dev/null 2>&1; then
    log 'OK qterminal: comando disponível'
  else
    log 'ERRO qterminal: comando não encontrado no PATH'
    issues=$((issues + 1))
  fi

  if [[ -f "$ICEWM_KEYS" ]] && grep -q '^key "Ctrl+Alt+t" qterminal$' "$ICEWM_KEYS"; then
    log 'OK icewm: Ctrl+Alt+t abre qterminal'
  else
    log 'ERRO icewm: Ctrl+Alt+t não está configurado para qterminal'
    issues=$((issues + 1))
  fi

  for pcmanfm_conf in "$PCMANFM_DEFAULT_CONF" "$PCMANFM_LXQT_CONF"; do
    if [[ -f "$pcmanfm_conf" ]] && grep -Fxq "Terminal=$PCMANFM_TERMINAL_COMMAND" "$pcmanfm_conf"; then
      log "OK pcmanfm: Terminal=$PCMANFM_TERMINAL_COMMAND em $pcmanfm_conf"
    else
      log "ERRO pcmanfm: Terminal=$PCMANFM_TERMINAL_COMMAND ausente em $pcmanfm_conf"
      issues=$((issues + 1))
    fi
  done

  if [[ -x "$PCMANFM_QTERMINAL_WRAPPER" ]] && /bin/sh -n "$PCMANFM_QTERMINAL_WRAPPER" 2>/dev/null; then
    log 'OK pcmanfm: wrapper qterminal executável e com sintaxe válida'
  else
    log "ERRO pcmanfm: wrapper inválido ou não executável: $PCMANFM_QTERMINAL_WRAPPER"
    issues=$((issues + 1))
  fi

  if [[ -x "$PCMANFM_TMUX_LAUNCHER" ]] && /bin/sh -n "$PCMANFM_TMUX_LAUNCHER" 2>/dev/null; then
    log 'OK pcmanfm: launcher tmux executável e com sintaxe válida'
  else
    log "ERRO pcmanfm: launcher tmux inválido ou não executável: $PCMANFM_TMUX_LAUNCHER"
    issues=$((issues + 1))
  fi

  if [[ -f "$PCMANFM_QTERMINAL_WRAPPER" ]] && \
     grep -Fq 'exec /usr/bin/qterminal --workdir "$dir" -e' "$PCMANFM_QTERMINAL_WRAPPER" && \
     grep -Fq 'PCMANFM_QTERMINAL_DIR="$dir"' "$PCMANFM_QTERMINAL_WRAPPER"; then
    log 'OK pcmanfm: wrapper chama qterminal com --workdir da pasta clicada'
  else
    log 'ERRO pcmanfm: wrapper não garante --workdir da pasta clicada'
    issues=$((issues + 1))
  fi

  if [[ -f "$PCMANFM_TMUX_LAUNCHER" ]] && \
     grep -Fq 'session=main' "$PCMANFM_TMUX_LAUNCHER" && \
     grep -Fq 'tmux new-window -P -F' "$PCMANFM_TMUX_LAUNCHER" && \
     grep -Fq -- '-t "$session" -c "$dir"' "$PCMANFM_TMUX_LAUNCHER" && \
     grep -Fq 'exec tmux new-session -s "$session" -c "$dir"' "$PCMANFM_TMUX_LAUNCHER"; then
    log 'OK pcmanfm: launcher tmux usa a sessão main na pasta clicada'
  else
    log 'ERRO pcmanfm: launcher tmux não usa a sessão main com -c "$dir"'
    issues=$((issues + 1))
  fi

  if command -v tmux >/dev/null 2>&1; then
    local pcman_sock="pcmanfm_qterm_check_$$"
    local pcman_check_dir
    local pcman_target
    local pcman_target_session
    local pcman_got_dir
    pcman_check_dir="$(mktemp -d)"
    if tmux -L "$pcman_sock" new-session -d -s main -c "$EFFECTIVE_HOME" >/dev/null 2>&1; then
      pcman_target="$(tmux -L "$pcman_sock" new-window -P -F '#{session_name}:#{window_index}' -t main -c "$pcman_check_dir" 2>/dev/null || true)"
      pcman_target_session="${pcman_target%%:*}"
      pcman_got_dir="$(tmux -L "$pcman_sock" display-message -p -t "$pcman_target" '#{pane_current_path}' 2>/dev/null || true)"
      tmux -L "$pcman_sock" kill-server >/dev/null 2>&1 || true
      if [[ "$pcman_target_session" == "main" && "$pcman_got_dir" == "$pcman_check_dir" ]]; then
        log 'OK tmux: nova window abre dentro da sessão main no diretório clicado'
      else
        log "ERRO tmux: window abriu em sessão=$pcman_target_session dir=$pcman_got_dir, esperado sessão=main dir=$pcman_check_dir"
        issues=$((issues + 1))
      fi
    else
      log 'ERRO tmux: não foi possível testar abertura de window na sessão main'
      issues=$((issues + 1))
    fi
    rmdir "$pcman_check_dir" >/dev/null 2>&1 || true
  fi

  if [[ -f "$QTERM_INI" ]]; then
    for key in "${SHORTCUT_KEYS[@]}"; do
      if grep -q "^${key}=$" "$QTERM_INI"; then
        log "OK qterminal.ini: $key limpo"
      else
        log "ERRO qterminal.ini: $key não está limpo"
        issues=$((issues + 1))
      fi
    done
    if grep -q '^SwapMouseButtons2and3=true$' "$QTERM_INI"; then
      log 'OK qterminal.ini: SwapMouseButtons2and3=true (direito->tmux, menu qterminal no botão do meio)'
    else
      log 'ERRO qterminal.ini: SwapMouseButtons2and3=true ausente'
      issues=$((issues + 1))
    fi
  else
    log "AVISO: $QTERM_INI não existe, validação dos atalhos do QTerminal foi pulada."
  fi

  if python3 - "$OMP_KEYBINDINGS" "$OMP_DIR" <<'PY'
import json
import sys
from pathlib import Path

root_path = Path(sys.argv[1])
omp_dir = Path(sys.argv[2])
required = {
    'tui.editor.deleteCharBackward': {'backspace', 'ctrl+h', 'ctrl+?'},
    'tui.editor.deleteWordBackward': {'ctrl+w', 'alt+backspace', 'ctrl+backspace'},
}

paths = [root_path]
profiles_dir = omp_dir / 'profiles'
if profiles_dir.exists():
    for agent_dir in sorted(profiles_dir.glob('*/agent')):
        if agent_dir.is_dir():
            paths.append(agent_dir / root_path.name)

errors = []
for path in paths:
    if not path.exists():
        errors.append(f'ausente:{path}')
        continue
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except Exception as exc:
        errors.append(f'erro-json:{path}:{exc}')
        continue

    if not isinstance(data, dict):
        errors.append(f'erro-formato:{path}:nao_objeto')
        continue

    missing = []
    for action, expected in required.items():
        value = data.get(action)
        if isinstance(value, str):
            got = {value}
        elif isinstance(value, list):
            got = {item for item in value if isinstance(item, str)}
        else:
            got = set()
        if not expected.issubset(got):
            missing.append(action)
    if missing:
        errors.append(f'faltando:{path}:{",".join(missing)}')

if errors:
    print('\n'.join(errors))
    sys.exit(1)
PY
  then
    log 'OK omp keybindings: default e perfis nomeados com delete backward em backspace/ctrl+h/ctrl+?'
    log 'OK omp keybindings: default e perfis nomeados com delete word backward em ctrl+w/alt+backspace/ctrl+backspace'
  else
    log 'ERRO omp keybindings: bindings obrigatórios ausentes em algum profile ou arquivo inválido'
    issues=$((issues + 1))
  fi

  if grep -q "@plugin 'tmux-plugins/tmux-resurrect'" "$TMUX_CONF" && \
     grep -q "@plugin 'tmux-plugins/tmux-continuum'" "$TMUX_CONF"; then
    log 'OK tmux.conf: plugins resurrect/continuum declarados'
  else
    log 'ERRO tmux.conf: declaração de resurrect/continuum ausente'
    issues=$((issues + 1))
  fi

  if [[ -d "$EFFECTIVE_HOME/.tmux/plugins/tmux-resurrect" && -d "$EFFECTIVE_HOME/.tmux/plugins/tmux-continuum" ]]; then
    log 'OK plugins: tmux-resurrect e tmux-continuum instalados'
  else
    log 'ERRO plugins: tmux-resurrect e/ou tmux-continuum não instalados'
    issues=$((issues + 1))
  fi

  if [[ "$issues" -eq 0 ]]; then
    log 'verificação concluída: tudo certo.'
  else
    log "verificação concluiu com $issues problema(s)."
    return 1
  fi
}

usage() {
  cat <<USAGE
Uso:
  $(basename "$0") [setup|setup-only|verify]

Modos:
  setup       Aplica configuração e verifica (padrão)
  setup-only  Só aplica configuração
  verify      Só verifica
USAGE
}

case "$MODE" in
  setup)
    apply_setup
    verify_setup
    ;;
  setup-only)
    apply_setup
    ;;
  verify)
    verify_setup
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
