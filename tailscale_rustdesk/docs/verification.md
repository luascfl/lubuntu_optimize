# Verification commands

Use these commands to verify the setup. Most require sudo.

## Power management

- Confirm logind lid switch handling:
  `grep -n "^HandleLidSwitch" /etc/systemd/logind.conf`
  `loginctl show-logind -p HandleLidSwitch -p HandleLidSwitchExternalPower -p HandleLidSwitchDocked -p IdleAction -p IdleActionSec`
- Confirm LXQt lid/idleness settings:
  `grep -E "enableLidWatcher|enableIdlenessWatcher|lidClosed" ~/.config/lxqt/lxqt-powermanagement.conf`
- Manual check: close the lid for a few minutes, then test remote access.

## RustDesk service

- Service status:
  `systemctl status rustdesk --no-pager`
- Enabled on boot:
  `systemctl is-enabled rustdesk`
- Verify user and Xvfb wrapper:
  `systemctl show rustdesk -p User -p Group -p ExecStart`
- Confirm Xvfb process:
  `pgrep -a Xvfb`

## SSH service

- Service status:
  `systemctl status ssh --no-pager`
- Enabled on boot:
  `systemctl is-enabled ssh`

## Tailscale

- Daemon status:
  `systemctl status tailscaled --no-pager`
- Connection status:
  `tailscale status`
  `tailscale ip -4`

## tmux

- List sessions:
  `tmux ls`
