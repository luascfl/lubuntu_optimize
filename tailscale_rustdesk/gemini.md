# contexto compacto

## resumo
- objetivo: notebook lubuntu sempre ligado, sem suspender ao fechar tampa, e acesso remoto estavel (rustdesk e/ou ssh + tailscale + tmux).
- prd gerado e tarefas criadas via taskmaster.
- principal automacao feita no script `scripts/setup_basic.sh`.

## estado atual
- tailscale funciona apos reboot.
- rustdesk instalado (1.4.4) e pacote .deb confirmado.
- rustdesk service esta habilitado mas para logo apos iniciar; `systemctl status rustdesk` mostra inactive (dead) e journal registra start -> stop rapido.
- `/run/rustdesk.pid` nao existe.
- config de logind mostra lid switch e idle action em ignore; lxqt powermanagement com lidClosedAction=0.
- senha permanente do rustdesk configurada no usuario.

## mudancas principais no projeto
### `scripts/setup_basic.sh`
- aplica logind: `HandleLidSwitch`, `HandleLidSwitchExternalPower`, `HandleLidSwitchDocked`, `IdleAction`, `IdleActionSec`.
- instala/ativa ssh, tailscale, tmux e rustdesk, com skip se ja instalados ou ativos.
- rustdesk: baixa ultima release ou usa `RUSTDESK_VERSION`/`RUSTDESK_DEB`.
- desativa tray por padrao: cria `~/.config/autostart/rustdesk-no-tray.desktop` e mata `rustdesk --tray` para `TRAY_USER`.
- flags: `CHECK_ONLY`, `VALIDATE`, `VALIDATE_ONLY`, `STATUS_FULL`, `DISABLE_TRAY`, `TRAY_USER`, `CONFIGURE_XSET`, `SKIP_APT_UPDATE`, `FORCE_INSTALL`.
- valida e mostra next steps somente se faltando tailscale conectado ou senha permanente.

### outros arquivos
- docs adicionados: `docs/always_on_setup.md`, `docs/verification.md`, `docs/checklist.md`.
- README atualizado com secao de conexao via android.
- `.taskmaster/docs/prd.md` criado e tasks geradas.

## problema pendente: rustdesk service morre no boot
- `rustdesk --service` parece encerrar rapido; systemd mata o cgroup.
- tentativa de ajuste: criar override do systemd para evitar kill automatico.

### override necessario (sem indentacao)
Arquivo: `/etc/systemd/system/rustdesk.service.d/override.conf`

Conteudo:
```
[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=none
```

Comandos para aplicar:
```
sudo mkdir -p /etc/systemd/system/rustdesk.service.d
cat <<'EOT' | sudo tee /etc/systemd/system/rustdesk.service.d/override.conf >/dev/null
[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=none
EOT
sudo systemctl daemon-reload
sudo systemctl restart rustdesk
sudo systemctl is-active rustdesk
pgrep -a rustdesk
```

## observacao importante
- este ambiente nao tem sudo funcional para editar `/etc` via tools, entao os comandos acima precisam rodar no terminal local.
