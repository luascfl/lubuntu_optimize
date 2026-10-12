# Setup guide for always on Lubuntu and remote access

This guide targets Lubuntu with LXQt and systemd. The goal is to keep the notebook awake, ignore lid close, and keep remote access available on boot.

## Power management in LXQt

The script sets these values automatically for the session user:
- disable lid watcher
- disable idleness watcher
- keep lid closed actions at "do nothing"

Settings live in `~/.config/lxqt/lxqt-powermanagement.conf` and are applied at next login.

## Power management in systemd logind

LXQt settings can be ignored on some systems when the lid closes. Force logind to ignore the lid switch.

1. Edit the file as root: `sudo featherpad /etc/systemd/logind.conf`
2. Add or set these keys:
   `HandleLidSwitch=ignore`
   `HandleLidSwitchExternalPower=ignore`
   `HandleLidSwitchDocked=ignore`
   `IdleAction=ignore`
   `IdleActionSec=0`
3. Save and restart logind: `sudo systemctl restart systemd-logind`

Note: closing the lid can still cut the backlight by hardware. The system remains awake and accessible, but the panel can look off until you open the lid and press a key.

## RustDesk as a system service

RustDesk needs the official .deb package to run as a systemd service before login.

1. Check the latest release tag:
   `curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep "tag_name"`
2. Download the .deb with the correct version:
   `curl -fL https://github.com/rustdesk/rustdesk/releases/download/<version>/rustdesk-<version>-x86_64.deb -o rustdesk-<version>-x86_64.deb`
3. Install:
   `sudo apt install ./rustdesk-<version>-x86_64.deb`
4. Enable and start the service:
   `sudo systemctl enable --now rustdesk`
5. Open RustDesk UI, set a permanent password, and confirm "Start with system" is enabled.

## CLI alternative: SSH + Tailscale + tmux

This is lighter than RustDesk and is ideal for tools like Claude Code, Gemini CLI, and Codex.

1. Install SSH server and enable it:
   `sudo apt update`
   `sudo apt install openssh-server`
   `sudo systemctl enable --now ssh`
2. Install Tailscale:
   `curl -fsSL https://tailscale.com/install.sh | sh`
3. Start and register the device:
   `sudo tailscale up`
4. Install tmux:
   `sudo apt install tmux`
5. Connect from another device:
   `ssh <user>@<tailscale-ip>`
   `tmux`

To detach a tmux session: press `Ctrl+b` then `d`. Reconnect with `tmux attach`.

## Tailscale key expiry

To avoid losing access after 180 days, disable key expiry in the Tailscale admin panel for this device.

## Optional automation script

Run the script to apply the systemd logind settings and install the tools:

`sudo ./scripts/setup_basic.sh`

Defaults:
- Installs SSH, Tailscale, tmux, and RustDesk when missing
- Applies logind settings shown above
- Disables LXQt lid watcher and idleness watcher for the session user
- Prints a validation summary and only shows next steps if needed

Optional environment flags:
- `CHECK_ONLY=1` to print RustDesk install and service status and exit
- `PRECHECK=0` to skip the automatic RustDesk status check at the start
- `FORCE_INSTALL=1` to reinstall packages even if they are already present
- `SKIP_APT_UPDATE=1` to skip `apt-get update` when packages are already installed
- `STATUS_FULL=1` to include full `systemctl status` output in status mode
- `DISABLE_TRAY=0` to keep the RustDesk tray in the user session
- `TRAY_USER=lucas` to select which user session gets the tray autostart override
- `LOGIND_VERIFY_DELAY=180` to control the login verification delay in seconds
- `VALIDATE=0` to skip the validation summary at the end
- `VALIDATE_ONLY=1` to run validation and exit without changes
- `RUSTDESK_VERSION=1.3.2` to pin a version
- `RUSTDESK_DEB=/path/to/rustdesk.deb` to install from a local file
- `CONFIGURE_XSET=1 LXQT_USER=<user>` to add an LXQt autostart entry that disables screen blanking

After the script, run: `sudo tailscale up`
