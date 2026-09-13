#!/usr/bin/env bash
set -u

MODE="${1:-diagnose}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_DIR="${REPORT_DIR:-$SCRIPT_DIR/reports}"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="${REPORT:-$REPORT_DIR/omp_clipboard_diag_$STAMP.md}"
TARGET_HOME="${TARGET_HOME:-$HOME}"
TMUX_CONF="${TMUX_CONF:-$TARGET_HOME/.tmux.conf}"
OMP_CLIPBOARD_TS="${OMP_CLIPBOARD_TS:-$TARGET_HOME/node_modules/@oh-my-pi/pi-coding-agent/src/utils/clipboard.ts}"

mkdir -p "$REPORT_DIR"

log() { printf '%s\n' "$*"; }
section() { printf '\n## %s\n\n' "$*" >> "$REPORT"; }
code() { printf '```text\n%s\n```\n\n' "$*" >> "$REPORT"; }
append_cmd() {
  local title="$1"
  shift
  section "$title"
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n'
    "$@"
    printf '\nexit=%s\n' "$?"
  } >> "$REPORT" 2>&1
}

have() { command -v "$1" >/dev/null 2>&1; }
run_with_timeout() {
  if have timeout; then
    timeout 3s "$@"
  else
    "$@"
  fi
}
read_clipboard() {
  if [[ -n "${DISPLAY:-}" ]] && have xclip; then
    run_with_timeout xclip -o -selection clipboard 2>/dev/null
    return $?
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && have wl-paste; then
    run_with_timeout wl-paste -n 2>/dev/null
    return $?
  fi
  if have xsel; then
    run_with_timeout xsel -ob 2>/dev/null
    return $?
  fi
  return 127
}
write_clipboard() {
  if [[ -n "${DISPLAY:-}" ]] && have xclip; then
    run_with_timeout xclip -selection clipboard -in -silent 2>/dev/null
    return $?
  fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && have wl-copy; then
    run_with_timeout wl-copy 2>/dev/null
    return $?
  fi
  if have xsel; then
    run_with_timeout xsel -ib 2>/dev/null
    return $?
  fi
  return 127
}

copy_backend_name() {
  if [[ -n "${DISPLAY:-}" ]] && have xclip; then printf 'xclip'; return; fi
  if [[ -n "${WAYLAND_DISPLAY:-}" ]] && have wl-copy; then printf 'wl-copy'; return; fi
  if have xsel; then printf 'xsel'; return; fi
  printf 'none'
}

base64_one_line() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w 0
  else
    base64 | tr -d '\n'
  fi
}

run_clipboard_probes() {
  section "Clipboard probes"
  local backend token got old osc_payload omp_token
  backend="$(copy_backend_name)"
  token="omp-clipboard-probe-$STAMP-$$"
  old="$(read_clipboard 2>/dev/null || true)"
  {
    printf 'backend=%s\n' "$backend"
    printf 'token=%s\n' "$token"
  } >> "$REPORT"

  if printf '%s' "$token" | write_clipboard; then
    got="$(read_clipboard 2>/dev/null || true)"
    if [[ "$got" == "$token" ]]; then
      printf 'native_clipboard_write_read=ok\n' >> "$REPORT"
    else
      printf 'native_clipboard_write_read=fail got=%q\n' "$got" >> "$REPORT"
    fi
  else
    printf 'native_clipboard_write_read=fail write_command_failed\n' >> "$REPORT"
  fi

  token="omp-osc52-probe-$STAMP-$$"
  osc_payload="$(printf '%s' "$token" | base64_one_line)"
  printf '\nAbout to emit OSC 52 token through the current terminal path.\n' >> "$REPORT"
  printf 'If QTerminal supports OSC 52 through tmux, clipboard should become: %s\n' "$token" >> "$REPORT"
  printf '\033]52;c;%s\a' "$osc_payload"
  sleep 1
  got="$(read_clipboard 2>/dev/null || true)"
  if [[ "$got" == "$token" ]]; then
    printf 'osc52_current_path=ok\n' >> "$REPORT"
  else
    printf 'osc52_current_path=fail got=%q\n' "$got" >> "$REPORT"
  fi

  omp_token="omp-native-probe-$STAMP-$$"
  printf '\nTesting OMP native clipboard binding via Bun import.\n' >> "$REPORT"
  if have bun && [[ -f "$TARGET_HOME/node_modules/@oh-my-pi/pi-natives/native/index.js" ]]; then
    if (cd "$TARGET_HOME" && BUN_JSC_useJIT="${BUN_JSC_useJIT:-0}" bun -e 'import { copyToClipboard } from "@oh-my-pi/pi-natives"; copyToClipboard(process.argv[1]);' "$omp_token") >> "$REPORT" 2>&1; then
      got="$(read_clipboard 2>/dev/null || true)"
      if [[ "$got" == "$omp_token" ]]; then
        printf 'omp_native_copyToClipboard=ok\n' >> "$REPORT"
      else
        printf 'omp_native_copyToClipboard=fail_returned_ok_but_clipboard=%q\n' "$got" >> "$REPORT"
      fi
    else
      printf 'omp_native_copyToClipboard=fail_command_error\n' >> "$REPORT"
    fi
  else
    printf 'omp_native_copyToClipboard=skipped bun_or_module_missing\n' >> "$REPORT"
  fi
  if [[ -n "$old" ]]; then
    printf '%s' "$old" | write_clipboard >/dev/null 2>&1 || true
  fi
}

apply_tmux_intervention() {
  local start end block tmp
  start='# >>> omp clipboard diagnostic intervention >>>'
  end='# <<< omp clipboard diagnostic intervention <<<'
  block=$(cat <<'EOF'
# OMP/QTerminal clipboard fallback.
# Direct tmux copy mode selections to the desktop clipboard command instead of relying only on OSC 52.
set -g set-clipboard on
set -as terminal-features ',xterm*:clipboard'
setw -g mode-keys vi
bind -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
bind -T copy-mode-vi Enter send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
bind -T copy-mode y send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
bind -T copy-mode Enter send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
bind -T copy-mode MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -selection clipboard -in -silent 2>/dev/null || wl-copy 2>/dev/null || xsel -ib 2>/dev/null"
EOF
)

  if [[ ! -f "$TMUX_CONF" ]]; then
    touch "$TMUX_CONF" || return 1
  fi
  tmp="$(mktemp)" || return 1
  python3 - "$TMUX_CONF" "$tmp" "$start" "$end" "$block" <<'PY'
from pathlib import Path
import re
import sys
src = Path(sys.argv[1])
dst = Path(sys.argv[2])
start, end, block = sys.argv[3], sys.argv[4], sys.argv[5]
text = src.read_text(encoding='utf-8') if src.exists() else ''
managed = f'{start}\n{block.rstrip()}\n{end}'
pattern = re.compile(re.escape(start) + r'.*?' + re.escape(end), re.S)
if pattern.search(text):
    text = pattern.sub(managed, text, count=1)
else:
    text = text.rstrip() + '\n\n' + managed + '\n'
dst.write_text(text, encoding='utf-8')
PY
  cp -a "$TMUX_CONF" "$TMUX_CONF.bak.$STAMP" 2>/dev/null || true
  cat "$tmp" > "$TMUX_CONF"
  rm -f "$tmp"
  if [[ -n "${TMUX:-}" ]] && have tmux; then
    tmux source-file "$TMUX_CONF" >/dev/null 2>&1 || true
  fi
}

apply_omp_local_intervention() {
  if [[ ! -f "$OMP_CLIPBOARD_TS" ]]; then
    log "OMP clipboard source not found: $OMP_CLIPBOARD_TS"
    return 1
  fi
  cp -a "$OMP_CLIPBOARD_TS" "$OMP_CLIPBOARD_TS.bak.$STAMP" || return 1
  python3 - "$OMP_CLIPBOARD_TS" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start = "\t// >>> local X11/Wayland clipboard fallback >>>"
end = "\t// <<< local X11/Wayland clipboard fallback <<<"
block = """\t// >>> local X11/Wayland clipboard fallback >>>
\t// Prefer deterministic desktop clipboard tools before the native binding.
\t// This works around native.copyToClipboard() returning success without updating X11 clipboard.
\tif (process.env.WAYLAND_DISPLAY) {
\t\ttry {
\t\t\texecSync(\"wl-copy\", { input: text, timeout: 2000 });
\t\t\treturn;
\t\t} catch {
\t\t\t// Fall through to X11/native.
\t\t}
\t}
\tif (process.env.DISPLAY) {
\t\ttry {
\t\t\texecSync(\"xclip -selection clipboard -in -silent\", { input: text, timeout: 2000 });
\t\t\treturn;
\t\t} catch {
\t\t\t// Fall through to native.
\t\t}
\t}
\t// <<< local X11/Wayland clipboard fallback <<<"""

if start in text and end in text:
    before, rest = text.split(start, 1)
    _, after = rest.split(end, 1)
    text = before + block + after
else:
    needle = "\n\t// Also try native tools (best effort for local sessions)\n"
    if needle not in text:
        raise SystemExit("patch anchor not found")
    text = text.replace(needle, "\n" + block + "\n" + needle, 1)
path.write_text(text, encoding="utf-8")
PY
}

generate_report() {
  : > "$REPORT"
  printf '# OMP clipboard diagnostic report\n\n' >> "$REPORT"
  printf 'Generated: %s\n\n' "$(date -Is)" >> "$REPORT"
  printf 'Purpose: diagnose OMP copy-message-to-clipboard failures in QTerminal + tmux.\n\n' >> "$REPORT"

  section "Interpretation"
  cat >> "$REPORT" <<'EOF'
Expected reading:

- `native_clipboard_write_read=ok` means the desktop clipboard is working through xclip, wl-copy or xsel.
- `osc52_current_path=fail` while native clipboard is ok means the terminal path is dropping OSC 52 clipboard escape sequences.
- `omp_native_copyToClipboard=fail_returned_ok_but_clipboard=...` means OMP's native binding returned success but did not update the desktop clipboard. That explains `/copy` failing even after the tmux fallback.
- The tmux intervention below only fixes tmux copy-mode selections by piping them to xclip/wl-copy/xsel. It cannot fix OMP's `/copy` if OMP uses a failing native binding and/or OSC 52 path.
EOF

  section "Environment"
  {
    printf 'USER=%s\n' "${USER:-}"
    printf 'SHELL=%s\n' "${SHELL:-}"
    printf 'TERM=%s\n' "${TERM:-}"
    printf 'TERM_PROGRAM=%s\n' "${TERM_PROGRAM:-}"
    printf 'COLORTERM=%s\n' "${COLORTERM:-}"
    printf 'DISPLAY=%s\n' "${DISPLAY:-}"
    printf 'WAYLAND_DISPLAY=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'XDG_SESSION_TYPE=%s\n' "${XDG_SESSION_TYPE:-}"
    printf 'TMUX=%s\n' "${TMUX:-}"
    printf 'TMUX_CONF=%s\n' "$TMUX_CONF"
  } >> "$REPORT"

  append_cmd "Kernel" uname -a
  if have qterminal; then append_cmd "QTerminal version" qterminal --version; else section "QTerminal version"; code "qterminal not found"; fi
  if have tmux; then append_cmd "tmux version" tmux -V; else section "tmux version"; code "tmux not found"; fi
  if have omp; then append_cmd "OMP version" omp --version; else section "OMP version"; code "omp not found in PATH"; fi

  section "Clipboard commands"
  {
    for cmd in xclip xsel wl-copy wl-paste qterminal tmux omp; do
      if have "$cmd"; then printf '%s=%s\n' "$cmd" "$(command -v "$cmd")"; else printf '%s=missing\n' "$cmd"; fi
    done
  } >> "$REPORT"

  if have tmux; then
    append_cmd "tmux global set-clipboard" tmux show-options -g set-clipboard
    append_cmd "tmux terminal-features" tmux show-options -g terminal-features
    append_cmd "tmux client info" tmux display-message -p 'client_termname=#{client_termname} client_tty=#{client_tty} pane_tty=#{pane_tty} version=#{version}'
    append_cmd "tmux copy-mode bindings" tmux list-keys -T copy-mode-vi
  fi

  if [[ -f "$TMUX_CONF" ]]; then
    section "Managed tmux clipboard lines"
    python3 - "$TMUX_CONF" >> "$REPORT" <<'PY'
from pathlib import Path
import sys
for i, line in enumerate(Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace').splitlines(), 1):
    low = line.lower()
    if any(term in low for term in ('clipboard', 'xclip', 'wl-copy', 'xsel', 'osc52', 'copy-pipe')):
        print(f'{i}: {line}')
PY
  fi

  run_clipboard_probes

  section "Issue summary template"
  cat >> "$REPORT" <<'EOF'
### Problem
OMP's copy-message-to-clipboard action does not update the system clipboard when running inside QTerminal + tmux on X11.

### Observed
Native clipboard commands work. OSC 52 through the current terminal path fails. OMP's native `@oh-my-pi/pi-natives.copyToClipboard()` binding can also return success without changing the X11 clipboard. tmux copy-mode can be made to work with `copy-pipe-and-cancel` to `xclip`, but OMP's `/copy` still fails.

### Expected
OMP should verify that the clipboard changed after copy, or expose/configure a deterministic platform clipboard command such as `xclip -selection clipboard -in -silent` on X11.

### Attached evidence
Paste this whole diagnostic report.
EOF
}

case "$MODE" in
  diagnose)
    generate_report
    log "Report written: $REPORT"
    ;;
  fix|intervene|apply)
    apply_tmux_intervention
    generate_report
    log "Intervention applied to: $TMUX_CONF"
    log "Backup: $TMUX_CONF.bak.$STAMP"
    log "Report written: $REPORT"
    ;;
  fix-omp-local)
    apply_omp_local_intervention
    generate_report
    log "Local OMP clipboard patch applied to: $OMP_CLIPBOARD_TS"
    log "Backup: $OMP_CLIPBOARD_TS.bak.$STAMP"
    log "Restart OMP before testing /copy."
    log "Report written: $REPORT"
    ;;
  help|-h|--help)
    cat <<EOF
Usage:
  $0 diagnose       # collect evidence, emit OSC 52/native probes, write report
  $0 fix            # add tmux copy-mode fallback, reload tmux, write report
  $0 fix-omp-local  # patch local OMP source to prefer xclip/wl-copy before native binding

Environment overrides:
  TARGET_HOME=/home/lucas
  TMUX_CONF=/home/lucas/.tmux.conf
  OMP_CLIPBOARD_TS=/home/lucas/node_modules/@oh-my-pi/pi-coding-agent/src/utils/clipboard.ts
  REPORT=/tmp/omp_clipboard.md
EOF
    ;;
  *)
    log "Unknown mode: $MODE"
    log "Run: $0 help"
    exit 2
    ;;
esac
