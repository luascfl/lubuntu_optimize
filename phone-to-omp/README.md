# phone-to-omp

`phone-to-omp` accepts a confirmed text prompt from the MacroDroid notification over Tailscale and types it into an existing `omp` tmux pane without pressing Enter. The phone macro is disabled in the sanitized template; importing it does not activate it.

When no `PHONE_TO_OMP_PANE` override is set, the receiver chooses the most recently active tmux pane currently running `omp`. It does not follow the visually focused pane across multiple tmux clients or sessions. Set `PHONE_TO_OMP_PANE` in the user service environment only when a fixed target is required.

## Prerequisites

- Python 3, tmux, systemd user services, and Tailscale on the computer.
- The computer must be authenticated to the intended tailnet. The installer does not authenticate a machine to Tailscale.
- A valid tailnet grant/ACL that allows only the intended phone to reach this computer on the selected port. The generated `tailscale-grant.pending.json` is a proposal only, not an applied policy.
- MacroDroid 5.65 or later, Google Play Services, and internet access on the phone for MacroDroid Remote. A connected Android device is needed only for the ADB fallback (`--push`).

## Install the receiver

Run from this directory. A bare invocation only displays help.

```sh
./install.sh status [GLOBAL OPTIONS]
./install.sh enable --phone NAME_OR_TAILSCALE_IP [--port 8765] [--firewall] [--ack-policy] [GLOBAL OPTIONS]
./install.sh disable [GLOBAL OPTIONS]
```

`enable` creates and preserves `~/.config/phone-to-omp/token`, creates `connection.json` with `host`, `port`, and `phone_ip`, writes `tailscale-grant.pending.json`, and applies only needed receiver/service changes. Apply that exact grant through the tailnet administrator, then use `--ack-policy` on a subsequent unchanged `enable` to record the acknowledgement. It does not test incoming connectivity.

`status` is read-only. `disable` restores only installer-owned receiver/service changes, removes an installer-owned UFW rule when it can identify that exact rule, and preserves credentials, connection settings, the pending grant, and private restoration backups.

Global options, accepted after the command, are:

```text
--target-home PATH                 default: $TARGET_HOME or $HOME
--config-dir PATH                  default: TARGET_HOME/.config/phone-to-omp
--state-dir PATH                   default: TARGET_HOME/.local/state/phone-to-omp
--python-command COMMAND           default or PHONE_TO_OMP_PYTHON_COMMAND
--tmux-command COMMAND             default or PHONE_TO_OMP_TMUX_COMMAND
--tailscale-command COMMAND        default or PHONE_TO_OMP_TAILSCALE_COMMAND
--systemctl-command COMMAND        default or PHONE_TO_OMP_SYSTEMCTL_COMMAND
--ufw-command COMMAND              default or PHONE_TO_OMP_UFW_COMMAND
--sudo-command COMMAND             default or PHONE_TO_OMP_SUDO_COMMAND
```

Use `--firewall` only when a local UFW rule is actually required. It limits the rule to the configured phone source, Tailscale interface, and configured TCP port; it does not configure tailnet grants.

## Render the private MacroDroid import

`notification-template.mdr.json` is the sanitized current MacroDroid export. It intentionally contains only these three placeholders in string values:

- `__OMP_HOST__`
- `__OMP_PORT__`
- `__OMP_TOKEN__`

It preserves the native MacroDroid schema, notification UI, prompt behavior, and disabled state. Do not invent or hand-write a MacroDroid payload if this template is absent: obtain and sanitize the current export first.

After `enable`, render a private import file at an explicit absolute path:

```sh
./macro-config.py \
  --output "$HOME/.config/phone-to-omp/imports/dictation-to-omp.mdr.json"
```

The complete renderer interface is:

```text
./macro-config.py [--template PATH] --output ABSOLUTE_PATH
                  [--config-dir PATH]
                  [--push SERIAL] [--adb PATH] [--remote-path ABSOLUTE_PHONE_PATH]
```

`--template` defaults to the sibling `notification-template.mdr.json`; use it to select a different sanitized current export. `--config-dir` defaults to `~/.config/phone-to-omp` and must contain private `token` and `connection.json` files. The latter must be an object with `host`, integer `port`, and `phone_ip` values. The renderer rejects missing, malformed, or non-private credentials; missing/invalid templates; absent or unknown OMP placeholders; and unresolved markers.

The output directory is created with mode `0700`; the rendered import file is mode `0600`. Rendering the same content again does not rewrite the file. The import contains the secret token, so keep it private and remove it from shared Android storage after use. The command never prints the token.

## Import and activate with MacroDroid Remote

Use [MacroDroid Remote](https://remote.macrodroid.com/) as the primary import and management path:

1. Sign in in the browser and MacroDroid with the same MacroDroid account, select the phone, and approve the first remote session on the phone if prompted.
2. Open **Macros**, choose **Import macro / category…**, and upload the private rendered `.mdr.json` file.
3. If MacroDroid offers to overwrite the same macro ID, confirm only after verifying that it is the intended `Dictation to omp` macro.
4. In **Macros**, explicitly activate `Dictation to omp`, then inspect the system log after a test request.
5. Delete the rendered private import file from the computer when it is no longer needed.

MacroDroid Remote does not replace Tailscale. It imports and manages the phone macro; the confirmed text still reaches the receiver through the private Tailscale connection.

## ADB fallback

Use ADB only when MacroDroid Remote is unavailable:

To copy the already-rendered file to a connected device and verify it byte-for-byte:

```sh
./macro-config.py \
  --output "$HOME/.config/phone-to-omp/imports/dictation-to-omp.mdr.json" \
  --push ANDROID_SERIAL
```

The default phone destination is `/sdcard/Download/phone-to-omp.mdr`. `--adb` selects the ADB executable, and `--remote-path` changes that destination. Copying does not import or activate the macro.

1. In MacroDroid, import the copied private file.
2. Its macro name is `Dictation to omp`. If MacroDroid offers to replace the same-name macro, explicitly confirm that replacement only after checking it is the intended existing macro. This controlled same-name replacement is user-confirmed behavior; do not assume every MacroDroid import is idempotent or cannot create duplicates.
3. From the MacroDroid **Macros** screen, activate `Dictation to omp`, then leave and reopen the screen to ensure the activation persisted.
4. Delete the private rendered import from shared phone storage when finished.

The `Dictate/send` button opens a native text prompt. Only confirmed text is sent. `Disable` disables this macro and clears its notification.
