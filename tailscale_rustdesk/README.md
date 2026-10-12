# Always-on Lubuntu + RustDesk + Tailscale

This repo documents a setup to keep a Lubuntu notebook always on and reachable.
It covers:
- power management hardening (LXQt + systemd logind)
- RustDesk running as a system service
- SSH + Tailscale + tmux for low-resource CLI access

## Quick start

Run the script as root:

```
sudo /home/lucas/Downloads/tailscale_rustdesk/scripts/setup_basic.sh
```

Defaults:
- applies logind settings to ignore lid close and idle actions
- keeps a single backup at /etc/systemd/logind.conf.bak (first run only)
- installs/enables SSH, Tailscale, tmux, RustDesk when missing and skips if already present
- disables RustDesk tray in the user session (service stays on)
- disables LXQt lid watcher and idleness watcher for the session user
- checks logind settings once per login after ~3 minutes and logs to ~/.local/state/logind-verify.log
- prints a validation summary at the end

## Validate only

```
VALIDATE_ONLY=1 /home/lucas/Downloads/tailscale_rustdesk/scripts/setup_basic.sh
```

## Useful flags

```
RUSTDESK_VERSION=1.4.5     # pin version
RUSTDESK_DEB=/path/file.deb
RUSTDESK_USER=lucas        # run RustDesk service as this user
DISABLE_TRAY=0             # keep tray
TRAY_USER=lucas            # user to apply tray override
CONFIGURE_XSET=1 LXQT_USER=lucas
LOGIND_VERIFY_DELAY=180    # seconds to wait before login check
CHECK_ONLY=1               # status only (RustDesk)
STATUS_FULL=1              # include systemctl status in CHECK_ONLY
VALIDATE=0                 # skip validation at end
```

## Manual steps (one-time)

1) RustDesk
- open UI and set a permanent password

2) Tailscale
- run `sudo tailscale up` once
- disable key expiry for the device in the admin panel

## Android access

### SSH (terminal)

1) Install Tailscale and sign in.
2) Install an SSH client (Termius, JuiceSSH, or ConnectBot).
3) Connect using:
   - Host: `100.94.142.32` or `lucas-inspiron3583`
   - User: `lucas`
   - Port: `22`

### RustDesk (screen)

1) Install RustDesk on Android.
2) Open RustDesk on the notebook, set a permanent password.
3) Enter the notebook ID in the Android app and connect using the password.

## Docs

- `docs/always_on_setup.md`
- `docs/verification.md`
- `docs/checklist.md`

## Notes

- closing the lid can still turn off the backlight by hardware, but the system stays awake
- use SSH + Tailscale for lowest resource usage when GUI is not needed
