# lubuntu_optimize

Documento rápido para alinhar o uso de ZRAM com o layout atual do notebook Dell Inspiron 3583 com 4 GiB RAM.

## Objetivo

Garantir que o kernel esteja usando o mesmo algoritmo de compressão solicitado em `/etc/default/zramswap`.

## Passos

1. **Confirmar e fixar o algoritmo desejado**
   - No `/etc/default/zramswap`, mantenha `ALGO=lz4` (a escolha preferida por ser rápida) ou mude para outro algoritmo suportado.
   - Use `zramctl` para checar o algoritmo ativo (`cat /sys/block/zram0/comp_algorithm`); a linha deve bater com o valor em `ALGO`.

2. **Recarregar o módulo zram com o algoritmo correto**
   ```bash
   sudo swapoff /dev/zram0
   sudo modprobe -r zram
   sudo modprobe zram algo=lz4
   sudo systemctl restart zramswap
   ```
   ou, se o serviço for diferente, substitua `zramswap` pelo serviço/dispositivo que sua distro usa.

3. **Verificar**
   - `zramctl` para confirmar `ALGO=lz4`, tamanho e compressão.
   - `free -h` e `swapon --show` para checar uso de swap.
   - Se usar `earlyoom`, este host usa limites `-m 20 -s 15` com ZRAM-only. Isso sacrifica conteúdo web pesado antes do congelamento total do desktop.

## Observações

- O ajuste mantém coerência entre o que você configura e o que o kernel aplica, evitando confusões com algos diferentes.
- Essa rotina pode ser incluída em scripts de provisionamento se você reinstala o sistema frequentemente.
- EarlyOOM usa limites `-m 20 -s 15` (`/etc/default/earlyoom`) e inclui `Isolated Web Co`/`Web Content` no `--prefer`, porque preservar guias pesadas causou congelamento completo. Como o swap em HDD (`/swapfile`) foi removido devido à extrema lentidão que ele causava, a política atual prefere matar a guia pesada a travar o sistema inteiro.

## Governança de cpugov-performance

- O serviço `cpugov-performance.service` agora tem asset versionado em `systemd/cpugov-performance.service` e exatamente um script de governança em `scripts/apply-cpugov-performance-service.sh`, que instala, habilita e verifica o estado final.
- Unit real instalada: `/etc/systemd/system/cpugov-performance.service`.
- Enable real esperado: `/etc/systemd/system/multi-user.target.wants/cpugov-performance.service`.
- Comando aplicado pela unit versionada: percorre `/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor` e grava `performance` em cada CPU com suporte a `cpufreq`.
- Fonte anterior conhecida: arquivo manual/local em `/etc/systemd/system`, com mtime observado `2025-09-10 22:36:34 -0300`; não havia gerador identificado em `lubuntu_optimize`.
- Instalação, habilitação e verificação em um comando:
  ```bash
  sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/apply-cpugov-performance-service.sh
  ```
  O verificador falha se a unit instalada divergir do asset versionado, se o serviço não estiver habilitado ou se algum governor suportado não estiver em `performance`.


## Monitoramento contínuo

- O script `scripts/zram-monitor.sh` (instalado em `/usr/local/bin/zram-monitor.sh`) coleta `free -h`, `zramctl`, `swapon --show` e `/proc/pressure/memory`, e grava em `/var/log/zram-monitor.log`.
- O script também verifica `free -m` e, se a memória disponível cai abaixo de 500 MiB ou o swap usado ultrapassa 1 GiB, registra a mensagem em `/var/log/zram-monitor-incidents.log` para manter um histórico de episódios “ruins”.
- Um `systemd` timer (`/etc/systemd/system/zram-monitor.timer`) dispara o script a cada 10 minutos (repita a chamada manualmente com `sudo systemctl start zram-monitor.service` se quiser um acionamento imediato).
- Verifique o histórico com `tail -n 40 /var/log/zram-monitor.log` ou `grep -n 'zramctl' /var/log/zram-monitor.log` para ver como o uso de swap evolui após alterações.
- Logrotate (`/etc/logrotate.d/zram-monitor`) mantém as últimas 6 rotações semanais dos logs, comprimindo e preservando incidentes mesmo que o timer rode continuamente.

## Evidência de congelamentos e desligamentos forçados

- O `early-oom/memory-guard.sh` concentra ZRAM, EarlyOOM e a evidência de congelamentos. Ele mantém snapshots de memória, swap, ZRAM, carga e PSI a cada minuto em `/var/log/memory-guard/memory-pressure.log`; sob pressão alta, também registra os processos com maior RSS.
- Use os dois scripts nesta ordem:
  1. `./optimize.sh apply` aplica somente os ajustes persistentes de kernel e zswap.
  2. `./early-oom/memory-guard.sh` instala e configura ZRAM, EarlyOOM e a pilha de monitoramento. Ele não grava valores `sysctl`.
- O EarlyOOM prioriza processos `Web Content` e `Isolated Web Co`, protegendo o processo principal do LibreWolf. Com RAM e ZRAM abaixo dos limites `-m 20 -s 15`, ele encerra uma aba pesada antes de o HDD entrar em thrashing.
- Para adicionar apenas a evidência de congelamentos, sem mudar ZRAM, EarlyOOM ou pacotes:
  ```bash
  ./early-oom/memory-guard.sh --logging-only
  ```
- Depois de um congelamento seguido de desligamento forçado e reinício, verifique:
  ```bash
  sudo journalctl --list-boots --no-pager
  sudo systemctl status memory-guard-session-log --no-pager
  sudo tail -n 50 /var/log/memory-guard/session-events.log
  sudo tail -n 120 /var/log/memory-guard/previous-boot-evidence.log
  ```

## Acesso root controlado

- O script `toggle-passwordless-sudo.sh` gerencia uma regra em `/etc/sudoers.d/99-omp-passwordless-<usuário>`.
- O perfil recomendado é `tuning`, que libera só os comandos de instalação e tuning deste repositório:
  ```bash
  sudo ./toggle-passwordless-sudo.sh enable --profile tuning
  sudo ./toggle-passwordless-sudo.sh status
  ```
- Quando o prompt de senha não aparecer no agente, use o modo PTY para abrir um terminal visível e rodar o mesmo `enable` via `sudo`:
  ```bash
  ./toggle-passwordless-sudo.sh enable --profile tuning --pty
  ```
- Se o conteúdo do helper mudar, rode `enable` de novo para regenerar a regra sudoers.
- O perfil `full` escreve `NOPASSWD: ALL` para o usuário alvo. Use só se você realmente quiser acesso root irrestrito:
  ```bash
  sudo ./toggle-passwordless-sudo.sh enable --profile full
  ```

## Instalação do monitor

- O helper `install-zram-monitor.sh` instala a cópia canônica `zram-monitor.sh` em `/usr/local/bin/zram-monitor.sh`.
- Com o perfil `tuning` ativo, o fluxo esperado é:
  ```bash
  sudo -n ./scripts/install-zram-monitor.sh
  sudo -n systemctl enable --now zram-monitor.timer
  sudo -n systemctl start zram-monitor.service
  ```
- Rollback:
  ```bash
  sudo -n systemctl stop zram-monitor.timer
  sudo -n systemctl disable zram-monitor.timer
  ```

## Aplicação de Otimizações de Kernel

- As otimizações de `vm.swappiness`, `vm.page-cluster` e `zswap` foram consolidadas no script unificado `optimize.sh`.
- Esse script é autossuficiente e trata a elevação de privilégios automaticamente:
  - Tenta rodar via `passwordless sudo` (se ativado pelo perfil `tuning`).
  - Se não houver regra passwordless, mas rodar em um terminal, pedirá a senha do `sudo` normalmente.
  - Se não houver terminal interativo (ex: rodando via atalho gráfico), abrirá uma interface (PTY) pedindo a senha.
- Para aplicar as otimizações persistentes recomendadas (Swappiness=80, Page Cluster=3, Zswap=0), rode:
  ```bash
  ./optimize.sh apply
  ```
- Ferramentas genéricas de benchmark (`run-kernel-memory-benchmark.sh`, `run-swappiness-benchmark.sh`, etc.) continuam disponíveis na raiz do repositório para testar configurações sob carga controlada.

## Decisão de Omitir HDD Swap (`/swapfile`)

- Em testes com HDD, transferir do ZRAM para o `/swapfile` quando a RAM lotava (ex: LibreWolf restaurando a sessão) causava *thrashing* profundo (o `swapoff` chegou a demorar mais de 2 minutos).
- Decidimos comentar o `/swapfile` no `/etc/fstab` e rodar `swapoff -a` (mantendo apenas o ZRAM), o que resulta em "falhas rápidas" (OOM Killer / EarlyOOM matando abas do LibreWolf) em vez de o sistema inteiro congelar irreversivelmente por minutos de leitura/escrita no HD lento.

## Resultado atual

- O `modprobe zram algo=lz4` alinhou o kernel ao `ALGO=lz4` do zramswap e `zramctl` agora reporta `/dev/zram0 lz4` com 1,8 GiB alocado e ~42 MiB comprimidos, exatamente como o README descreve.
- `swapon --show` retorna o dispositivo `/dev/zram0` (1,8 GiB, prioridade 100) ativo de imediato e `free -h` mostra 1,8 GiB de swap com ~193 MiB em uso, confirmando que a troca voltou a funcionar com o novo algoritmo.
- Um benchmark controlado com `scripts/run-swappiness-benchmark.sh` apontou `89` como o melhor valor final: a primeira rodada mostrou que `80` era melhor que `110`, `90` e `60`, e a rodada fina seguinte mostrou que `89` superou `87` com menos swap e menos pressure, enquanto `90` voltou a piorar. O valor persistido agora é `89` em `/etc/sysctl.d/99-lubuntu-optimize-swappiness.conf`. O rollback permanece `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-swappiness-persistent.sh 110`.
- Um benchmark controlado com `scripts/run-page-cluster-benchmark.sh` apontou `2` como o melhor valor final de `vm.page-cluster` entre `0`, `1`, `2` e `3`: contra `0`, o valor `2` reduziu o swap de `1318 MiB` para `1309 MiB` e baixou a pressure de `some avg60=0.35` / `full avg60=0.09` para `some avg60=0.22` / `full avg60=0.04`, mantendo a memória disponível acima de `1 GiB`. O valor persistido agora é `2` em `/etc/sysctl.d/99-lubuntu-optimize-page-cluster.conf`. O rollback permanece `sudo -n /home/lucas/Downloads/lubuntu_optimize/scripts/set-page-cluster-persistent.sh 0`.
- Um benchmark controlado com `scripts/run-zswap-benchmark.sh` mostrou que `zswap=1` piora este notebook em comparação com `zswap=0`: sob a mesma carga, a memória disponível subiu de `410 MiB` para `650 MiB`, mas o swap total subiu de `1227 MiB` para `1441 MiB` e a pressure piorou de `some avg60=2.20` / `full avg60=1.43` para `some avg60=7.04` / `full avg60=4.41`. A decisão final é manter `zswap` desativado. O rollback permanece `sudo -n ./scripts/set-zswap-enabled.sh 0`.
