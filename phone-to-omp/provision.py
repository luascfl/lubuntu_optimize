#!/usr/bin/env python3
"""Idempotent local provisioning for the phone-to-omp receiver.

This program deliberately manages only local files, the per-user systemd unit, and
an optional narrow UFW rule.  It never logs in to Tailscale or changes tailnet
policy; it writes the proposed one-rule grant for an administrator to apply.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import ipaddress
import json
import os
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

APP = "phone-to-omp"
DEFAULT_PORT = 8765
SOURCE = Path(__file__).with_name("phone_to_omp.py")


class ProvisionError(RuntimeError):
    pass


@dataclass(frozen=True)
class Paths:
    home: Path
    config: Path
    state: Path
    binary: Path
    unit: Path

    @property
    def token(self) -> Path:
        return self.config / "token"

    @property
    def connection(self) -> Path:
        return self.config / "connection.json"

    @property
    def grant(self) -> Path:
        return self.config / "tailscale-grant.pending.json"

    @property
    def ownership(self) -> Path:
        return self.state / "ownership.json"


@dataclass(frozen=True)
class Commands:
    python: tuple[str, ...]
    tmux: tuple[str, ...]
    tailscale: tuple[str, ...]
    systemctl: tuple[str, ...]
    ufw: tuple[str, ...]
    sudo: tuple[str, ...]


def split_command(value: str, option: str) -> tuple[str, ...]:
    command = tuple(shlex.split(value))
    if not command:
        raise ProvisionError(f"{option} must name a command")
    return command


def command_available(command: tuple[str, ...]) -> bool:
    executable = command[0]
    return (Path(executable).is_file() and os.access(executable, os.X_OK)) if "/" in executable else shutil.which(executable) is not None


def require_command(label: str, command: tuple[str, ...]) -> None:
    if not command_available(command):
        raise ProvisionError(f"missing prerequisite {label}: {command_text(command)}")


def command_text(command: tuple[str, ...]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def run(
    command: tuple[str, ...],
    *args: str,
    check: bool = False,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = None if environment is None else {**os.environ, **environment}
    try:
        completed = subprocess.run(
            [*command, *args], text=True, capture_output=True, timeout=15, check=False, env=env
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise ProvisionError(f"could not run {command_text(command)}: {exc}") from exc
    if check and completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise ProvisionError(f"{command_text(command)} {' '.join(args)} failed: {detail}")
    return completed


def existing_mode(path: Path) -> int | None:
    try:
        return stat.S_IMODE(path.stat().st_mode)
    except FileNotFoundError:
        return None


def content_equals(path: Path, content: bytes) -> bool:
    try:
        return path.read_bytes() == content
    except FileNotFoundError:
        return False


def ensure_directory(path: Path, mode: int) -> bool:
    changed = False
    if not path.exists():
        path.mkdir(parents=True, mode=mode)
        changed = True
    elif not path.is_dir():
        raise ProvisionError(f"required directory path is not a directory: {path}")
    if existing_mode(path) != mode:
        path.chmod(mode)
        changed = True
    return changed


def write_if_different(path: Path, content: bytes, mode: int) -> bool:
    if content_equals(path, content) and existing_mode(path) == mode:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(content)
        os.chmod(temporary, mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def load_json(path: Path, description: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ProvisionError(f"missing {description}: {path}")
    except (OSError, json.JSONDecodeError) as exc:
        raise ProvisionError(f"invalid {description}: {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ProvisionError(f"invalid {description}: {path} is not an object")
    return payload


def compact_json(value: dict[str, Any]) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")


def systemd_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unit_content(paths: Paths, port: int) -> bytes:
    return (
        "# Managed by phone-to-omp provision.py; restoration metadata is private.\n"
        "[Unit]\n"
        "Description=Type phone dictation into omp over Tailscale\n"
        "After=network-online.target\n\n"
        "[Service]\n"
        f"Environment=PHONE_TO_OMP_DIR={systemd_quote(str(paths.config))}\n"
        f"Environment=PHONE_TO_OMP_PORT={port}\n"
        f"ExecStart={systemd_quote(str(paths.binary))}\n"
        "Restart=always\n"
        "RestartSec=5\n\n"
        "[Install]\n"
        "WantedBy=default.target\n"
    ).encode("utf-8")


def binary_content(commands: Commands) -> bytes:
    try:
        source = SOURCE.read_bytes()
    except OSError as exc:
        raise ProvisionError(f"receiver source unavailable: {SOURCE}: {exc}") from exc
    if not source.startswith(b"#!"):
        raise ProvisionError(f"receiver source has no interpreter line: {SOURCE}")
    _, body = source.split(b"\n", 1)
    interpreter = commands.python[0]
    if not os.path.isabs(interpreter):
        resolved = shutil.which(interpreter)
        if resolved is None:
            raise ProvisionError(f"python interpreter unavailable: {interpreter}")
        interpreter = resolved
    return f"#!{interpreter}\n".encode("utf-8") + body


def paths_for(args: argparse.Namespace) -> Paths:
    home = Path(args.target_home).expanduser().resolve()
    config = Path(args.config_dir).expanduser().resolve() if args.config_dir else home / ".config" / APP
    state = Path(args.state_dir).expanduser().resolve() if args.state_dir else home / ".local" / "state" / APP
    return Paths(home, config, state, home / ".local" / "bin" / APP, home / ".config" / "systemd" / "user" / f"{APP}.service")


def commands_for(args: argparse.Namespace) -> Commands:
    def value(name: str, default: str) -> tuple[str, ...]:
        return split_command(getattr(args, name) or os.environ.get(f"PHONE_TO_OMP_{name.upper()}_COMMAND") or default, f"--{name.replace('_', '-')}-command")

    return Commands(
        python=value("python", sys.executable),
        tmux=value("tmux", "tmux"),
        tailscale=value("tailscale", "tailscale"),
        systemctl=value("systemctl", "systemctl"),
        ufw=value("ufw", "ufw"),
        sudo=value("sudo", "sudo"),
    )


def require_enable_prerequisites(commands: Commands) -> None:
    for label, command in (
        ("Python", commands.python),
        ("tmux", commands.tmux),
        ("tailscale", commands.tailscale),
        ("systemctl", commands.systemctl),
    ):
        require_command(label, command)


def service_enabled(commands: Commands) -> bool:
    return run(commands.systemctl, "--user", "is-enabled", "--quiet", APP).returncode == 0


def service_active(commands: Commands) -> bool:
    return run(commands.systemctl, "--user", "is-active", "--quiet", APP).returncode == 0


def service_snapshot(commands: Commands) -> dict[str, bool]:
    return {"enabled": service_enabled(commands), "active": service_active(commands)}


def require_systemd_user(commands: Commands) -> None:
    require_command("systemctl", commands.systemctl)
    run(commands.systemctl, "--user", "--version", check=True)


def tailscale_state(commands: Commands) -> tuple[str, dict[str, Any]]:
    require_command("tailscale", commands.tailscale)
    ip_result = run(commands.tailscale, "ip", "-4", check=True)
    ips = [line.strip() for line in ip_result.stdout.splitlines() if line.strip()]
    if len(ips) != 1:
        raise ProvisionError("Tailscale must report exactly one IPv4 address; connect this PC to the intended tailnet")
    try:
        host_ip = str(ipaddress.IPv4Address(ips[0]))
    except ipaddress.AddressValueError as exc:
        raise ProvisionError(f"Tailscale returned an invalid IPv4 address: {ips[0]!r}") from exc
    status = run(commands.tailscale, "status", "--json", check=True)
    try:
        payload = json.loads(status.stdout)
    except json.JSONDecodeError as exc:
        raise ProvisionError("Tailscale status did not return JSON; verify authenticated Tailscale access") from exc
    if not isinstance(payload, dict):
        raise ProvisionError("Tailscale status JSON is not an object")
    backend_state = payload.get("BackendState")
    if backend_state not in ("Running", "NeedsLogin") and not payload.get("Self"):
        raise ProvisionError("Tailscale is not running; connect this PC to the intended tailnet")
    if backend_state == "NeedsLogin":
        raise ProvisionError("Tailscale needs login; authenticate this PC explicitly before enabling")
    return host_ip, payload


def peer_entries(status: dict[str, Any]) -> list[dict[str, Any]]:
    peers = status.get("Peer", {})
    if isinstance(peers, dict):
        return [peer for peer in peers.values() if isinstance(peer, dict)]
    if isinstance(peers, list):
        return [peer for peer in peers if isinstance(peer, dict)]
    return []


def candidate_ips(peer: dict[str, Any]) -> set[str]:
    values = peer.get("TailscaleIPs", [])
    if not isinstance(values, list):
        return set()
    return {str(value) for value in values if isinstance(value, str)}


def resolve_phone(phone: str, status: dict[str, Any]) -> str:
    try:
        requested_ip = str(ipaddress.IPv4Address(phone))
    except ipaddress.AddressValueError:
        requested_ip = None
    matches: list[dict[str, Any]] = []
    for peer in peer_entries(status):
        if requested_ip:
            if requested_ip in candidate_ips(peer):
                matches.append(peer)
            continue
        names = {str(peer.get(key, "")).rstrip(".") for key in ("DNSName", "HostName", "Name")}
        dns_name = str(peer.get("DNSName", "")).rstrip(".")
        if dns_name:
            names.add(dns_name.split(".", 1)[0])
        if phone.rstrip(".") in names:
            matches.append(peer)
    if not matches:
        raise ProvisionError(f"phone {phone!r} was not found in Tailscale status; reconnect it or provide its exact current Tailscale name/IP")
    if len(matches) != 1:
        raise ProvisionError(f"phone {phone!r} is ambiguous in Tailscale status; provide its exact Tailscale IPv4 address")
    ips = sorted(ip for ip in candidate_ips(matches[0]) if "." in ip)
    if len(ips) != 1:
        raise ProvisionError(f"phone {phone!r} does not have exactly one Tailscale IPv4 address")
    return ips[0]


def token_is_present(paths: Paths) -> bool:
    try:
        return bool(paths.token.read_text(encoding="utf-8").strip())
    except OSError:
        return False


def make_connection(host: str, port: int, phone_ip: str) -> bytes:
    return compact_json({"host": host, "phone_ip": phone_ip, "port": port})


def make_grant(host: str, port: int, phone_ip: str) -> bytes:
    return compact_json({"grants": [{"dst": [host], "ip": [f"tcp:{port}"], "src": [phone_ip]}]})


def policy_fingerprint(host: str, port: int, phone_ip: str) -> str:
    return hashlib.sha256(make_grant(host, port, phone_ip)).hexdigest()


def load_ownership(paths: Paths) -> dict[str, Any]:
    if not paths.ownership.exists():
        return {"version": 1, "files": {}}
    data = load_json(paths.ownership, "ownership state")
    if data.get("version") != 1 or not isinstance(data.get("files"), dict):
        raise ProvisionError(f"unsupported ownership state: {paths.ownership}")
    return data


def snapshot_file(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"existed": False}
    if not path.is_file():
        raise ProvisionError(f"managed path is not a regular file: {path}")
    return {"existed": True, "content": base64.b64encode(path.read_bytes()).decode("ascii"), "mode": existing_mode(path)}


def record_once(state: dict[str, Any], key: str, path: Path) -> bool:
    files = state["files"]
    if key in files:
        return False
    files[key] = snapshot_file(path)
    return True


def save_ownership(paths: Paths, state: dict[str, Any]) -> bool:
    return write_if_different(paths.ownership, compact_json(state), 0o600)


def ensure_private_dirs(paths: Paths) -> bool:
    changed = ensure_directory(paths.config, 0o700)
    changed = ensure_directory(paths.state, 0o700) or changed
    return changed


def ensure_token(paths: Paths) -> bool:
    if token_is_present(paths):
        if existing_mode(paths.token) != 0o600:
            paths.token.chmod(0o600)
            return True
        return False
    return write_if_different(paths.token, (secrets.token_urlsafe(32) + "\n").encode("ascii"), 0o600)


def ufw_status(commands: Commands) -> tuple[bool, str]:
    require_command("sudo", commands.sudo)
    require_command("ufw", commands.ufw)
    result = run(
        (*commands.sudo, *commands.ufw),
        "status",
        "numbered",
        environment={"LC_ALL": "C", "LANG": "C"},
    )
    text = result.stdout + result.stderr
    if result.returncode != 0:
        raise ProvisionError(f"could not inspect UFW using sudo: {text.strip() or 'unknown failure'}")
    match = re.search(r"^Status:\s*(active|inactive)\s*$", text, flags=re.MULTILINE)
    if match is None:
        raise ProvisionError("could not determine UFW state from canonical output")
    return match.group(1) == "active", text


def added_ufw_rules(commands: Commands) -> str:
    result = run(
        (*commands.sudo, *commands.ufw),
        "show",
        "added",
        environment={"LC_ALL": "C", "LANG": "C"},
    )
    text = result.stdout + result.stderr
    if result.returncode != 0:
        raise ProvisionError(f"could not inspect UFW rules using sudo: {text.strip() or 'unknown failure'}")
    return text


def matching_ufw_rules(text: str, host: str, port: int, phone_ip: str) -> list[str]:
    expected = " ".join(
        (
            "ufw",
            "allow",
            "in",
            "on",
            "tailscale0",
            "from",
            phone_ip.lower(),
            "to",
            host.lower(),
            "port",
            str(port),
            "proto",
            "tcp",
        )
    )
    return [line for line in text.splitlines() if " ".join(line.lower().split()) == expected]


def same_firewall_target(firewall: dict[str, Any], host: str, port: int, phone_ip: str) -> bool:
    return (
        firewall.get("host") == host
        and firewall.get("port") == port
        and firewall.get("phone_ip") == phone_ip
    )


def enable_firewall(commands: Commands, state: dict[str, Any], host: str, port: int, phone_ip: str) -> bool:
    firewall = state.get("firewall")
    if isinstance(firewall, dict) and firewall.get("owned") and not same_firewall_target(firewall, host, port, phone_ip):
        raise ProvisionError("refusing to replace an owned UFW rule for changed phone/host/port; run disable --firewall first")
    active, text = ufw_status(commands)
    if not active:
        print("already ok: UFW inactive; no firewall rule is needed")
        return False
    matches = matching_ufw_rules(added_ufw_rules(commands), host, port, phone_ip)
    if matches:
        if not firewall:
            state["firewall"] = {"owned": False, "host": host, "port": port, "phone_ip": phone_ip}
            return True
        return False
    run(
        (*commands.sudo, *commands.ufw),
        "allow",
        "in",
        "on",
        "tailscale0",
        "from",
        phone_ip,
        "to",
        host,
        "port",
        str(port),
        "proto",
        "tcp",
        check=True,
        environment={"LC_ALL": "C", "LANG": "C"},
    )
    state["firewall"] = {"owned": True, "host": host, "port": port, "phone_ip": phone_ip}
    return True


def disable_firewall(commands: Commands, state: dict[str, Any]) -> bool:
    firewall = state.get("firewall")
    if not isinstance(firewall, dict) or not firewall.get("owned"):
        print("already disabled: no owned UFW rule")
        return True
    active, _ = ufw_status(commands)
    if not active:
        print("preserved: owned UFW rule while UFW is inactive")
        return False
    matches = matching_ufw_rules(
        added_ufw_rules(commands),
        str(firewall["host"]),
        int(firewall["port"]),
        str(firewall["phone_ip"]),
    )
    if len(matches) != 1:
        print("preserved: owned UFW rule could not be identified uniquely")
        return False
    run(
        (*commands.sudo, *commands.ufw),
        "delete",
        "allow",
        "in",
        "on",
        "tailscale0",
        "from",
        str(firewall["phone_ip"]),
        "to",
        str(firewall["host"]),
        "port",
        str(firewall["port"]),
        "proto",
        "tcp",
        check=True,
        environment={"LC_ALL": "C", "LANG": "C"},
    )
    firewall["owned"] = False
    print("removed: owned UFW rule")
    return True


def enable(args: argparse.Namespace, paths: Paths, commands: Commands) -> int:
    if not args.phone:
        raise ProvisionError("enable requires --phone NAME_OR_TAILSCALE_IP; the phone is never selected implicitly")
    require_enable_prerequisites(commands)
    require_systemd_user(commands)
    host, status = tailscale_state(commands)
    phone_ip = resolve_phone(args.phone, status)
    if phone_ip == host:
        raise ProvisionError("--phone identifies this PC, not a phone")
    state = load_ownership(paths)
    firewall = state.get("firewall")
    if isinstance(firewall, dict) and firewall.get("owned") and not same_firewall_target(firewall, host, args.port, phone_ip):
        raise ProvisionError("refusing to change phone/host/port while an owned UFW rule exists; run disable first")
    dirs_changed = ensure_private_dirs(paths)
    state_changed = record_once(state, "binary", paths.binary)
    state_changed = record_once(state, "unit", paths.unit) or state_changed
    if "service_before" not in state:
        state["service_before"] = service_snapshot(commands)
        state_changed = True
    if state.get("managed_port") != args.port:
        state["managed_port"] = args.port
        state_changed = True
    if state.pop("disabled", False):
        state_changed = True
    if args.ack_policy:
        acknowledgement = policy_fingerprint(host, args.port, phone_ip)
        if state.get("policy_ack") != acknowledgement:
            state["policy_ack"] = acknowledgement
            state_changed = True
    elif state.get("policy_ack") and state["policy_ack"] != policy_fingerprint(host, args.port, phone_ip):
        state.pop("policy_ack")
        state_changed = True
    if state_changed:
        save_ownership(paths, state)
    token_changed = ensure_token(paths)
    connection_changed = write_if_different(paths.connection, make_connection(host, args.port, phone_ip), 0o600)
    grant_changed = write_if_different(paths.grant, make_grant(host, args.port, phone_ip), 0o600)
    binary_changed = write_if_different(paths.binary, binary_content(commands), 0o755)
    unit_changed = write_if_different(paths.unit, unit_content(paths, args.port), 0o644)
    changed = any((dirs_changed, token_changed, connection_changed, grant_changed, binary_changed, unit_changed))
    if binary_changed or unit_changed:
        run(commands.systemctl, "--user", "daemon-reload", check=True)
    enabled = service_enabled(commands)
    active = service_active(commands)
    if not enabled:
        run(commands.systemctl, "--user", "enable", APP, check=True)
        print("applied: user service enabled")
    if binary_changed or unit_changed:
        run(commands.systemctl, "--user", "restart", APP, check=True)
        print("applied: user service restarted for changed files")
    elif not active:
        run(commands.systemctl, "--user", "start", APP, check=True)
        print("applied: user service started")
    else:
        print("already ok: user service enabled and active")
    if args.firewall:
        if enable_firewall(commands, state, host, args.port, phone_ip):
            save_ownership(paths, state)
            print("applied: narrow UFW rule")
        else:
            print("already ok: firewall state")
    else:
        print("not changed: UFW (pass --firewall to manage a narrow tailscale0 rule)")
    if changed:
        print("applied: local receiver configuration")
    else:
        print("already ok: local receiver configuration")
    if args.ack_policy:
        print("acknowledged: external policy matches this host, phone, and port; incoming connectivity is not verified")
    else:
        print(f"pending external action: apply {paths.grant} to the existing tailnet policy with administrator authentication; it was not installed automatically")
    print("pending external action: update and explicitly activate the phone macro with connection.json and token; this installer cannot verify the phone")
    return 0


def restore_file(record: dict[str, Any], path: Path, managed_content: bytes) -> bool:
    if not content_equals(path, managed_content):
        return False
    if record.get("existed"):
        content = base64.b64decode(record["content"])
        mode = int(record["mode"])
        write_if_different(path, content, mode)
    else:
        path.unlink(missing_ok=True)
    return True


def disable(args: argparse.Namespace, paths: Paths, commands: Commands) -> int:
    state = load_ownership(paths)
    if state.get("disabled"):
        print("already disabled: local receiver changes were already restored")
        print("preserved: token, connection settings, pending grant, and private restoration backups")
        return 0
    files = state["files"]
    binary_restore = files.get("binary")
    unit_restore = files.get("unit")
    if not isinstance(binary_restore, dict) and not isinstance(unit_restore, dict):
        print("already disabled: no owned local receiver changes")
        print("preserved: token, connection settings, pending grant, and private restoration backups")
        return 0
    port = state.get("managed_port", DEFAULT_PORT)
    if not isinstance(port, int) or not 1 <= port <= 65535:
        raise ProvisionError("ownership state has an invalid managed port")
    binary = binary_content(commands)
    unit = unit_content(paths, port)
    unit_was_managed = isinstance(unit_restore, dict) and content_equals(paths.unit, unit)
    if unit_was_managed:
        require_systemd_user(commands)
        run(commands.systemctl, "--user", "stop", APP)
        run(commands.systemctl, "--user", "disable", APP)
    binary_done = isinstance(binary_restore, dict) and restore_file(binary_restore, paths.binary, binary)
    unit_done = isinstance(unit_restore, dict) and restore_file(unit_restore, paths.unit, unit)
    if unit_done:
        run(commands.systemctl, "--user", "daemon-reload", check=True)
    before = state.get("service_before")
    if unit_done and isinstance(before, dict) and before.get("enabled"):
        run(commands.systemctl, "--user", "enable", APP, check=True)
    if unit_done and isinstance(before, dict) and before.get("active"):
        run(commands.systemctl, "--user", "restart", APP, check=True)
    if binary_done:
        print("removed: managed receiver binary (original content restored when present)")
    else:
        print("preserved: receiver binary was not the managed content")
    if unit_done:
        print("removed: managed user unit (original content restored when present)")
    else:
        print("preserved: user unit was not the managed content")
    firewall = state.get("firewall")
    firewall_removed = True
    if isinstance(firewall, dict) and firewall.get("owned"):
        firewall_removed = disable_firewall(commands, state)
    else:
        print("already disabled: no owned UFW rule")
    if firewall_removed:
        state["disabled"] = True
    save_ownership(paths, state)
    print("preserved: token, connection settings, pending grant, and private restoration backups")
    return 0


def status(args: argparse.Namespace, paths: Paths, commands: Commands) -> int:
    failures = 0

    def report(ok: bool, label: str, reason: str = "") -> None:
        nonlocal failures
        print(("[ok]" if ok else "[missing]") + f" {label}" + (f": {reason}" if reason else ""))
        if not ok:
            failures += 1

    availability = {}
    for label, command in (
        ("Python", commands.python),
        ("tmux", commands.tmux),
        ("systemctl", commands.systemctl),
        ("tailscale", commands.tailscale),
    ):
        available = command_available(command)
        availability[label] = available
        report(available, label, command_text(command) if available else f"install or set --{label.lower()}-command")
    if availability["systemctl"]:
        try:
            require_systemd_user(commands)
            report(True, "systemd user service support")
        except ProvisionError as exc:
            report(False, "systemd user service support", str(exc))
    else:
        report(False, "systemd user service support", "systemctl is unavailable")
    if availability["tailscale"]:
        try:
            host, _ = tailscale_state(commands)
            report(True, "Tailscale PC IPv4", host)
        except ProvisionError as exc:
            host = ""
            report(False, "Tailscale PC IPv4", str(exc))
    else:
        host = ""
        report(False, "Tailscale PC IPv4", "tailscale is unavailable")
    report(token_is_present(paths), "private token", str(paths.token))
    connection: dict[str, Any] = {}
    try:
        connection = load_json(paths.connection, "connection configuration")
        connection_ok = (
            isinstance(connection.get("host"), str)
            and isinstance(connection.get("phone_ip"), str)
            and isinstance(connection.get("port"), int)
            and 1 <= connection["port"] <= 65535
        )
        if connection_ok and host and connection["host"] != host:
            report(False, "connection configuration", "configured host differs from current Tailscale PC IPv4")
            connection_ok = False
        else:
            report(connection_ok, "connection configuration", str(paths.connection))
    except ProvisionError as exc:
        report(False, "connection configuration", str(exc))
        connection_ok = False
    report(paths.grant.exists(), "proposed narrow tailnet grant", str(paths.grant))
    try:
        expected_binary = binary_content(commands)
        report(content_equals(paths.binary, expected_binary) and existing_mode(paths.binary) == 0o755, "receiver binary", str(paths.binary))
    except ProvisionError as exc:
        report(False, "receiver binary", str(exc))
    if connection_ok:
        report(
            content_equals(paths.unit, unit_content(paths, connection["port"])) and existing_mode(paths.unit) == 0o644,
            "user unit",
            str(paths.unit),
        )
    else:
        report(False, "user unit", "connection configuration is unavailable")
    if availability["systemctl"]:
        try:
            report(service_enabled(commands), "user service enabled")
            report(service_active(commands), "user service active")
        except ProvisionError as exc:
            report(False, "user service state", str(exc))
    else:
        report(False, "user service state", "systemctl is unavailable")
    acknowledged = False
    if connection_ok:
        try:
            state = load_ownership(paths)
            acknowledged = state.get("policy_ack") == policy_fingerprint(
                connection["host"], connection["port"], connection["phone_ip"]
            )
        except ProvisionError as exc:
            report(False, "tailnet policy acknowledgement", str(exc))
    report(
        acknowledged,
        "external tailnet authorization",
        "acknowledged for this exact host/phone/port; incoming connectivity remains unverified"
        if acknowledged
        else "apply the exact pending grant through existing tailnet administration, then enable with --ack-policy; this installer never changes ACLs/grants",
    )
    report(
        False,
        "phone endpoint/token activation",
        "unverified: update and explicitly activate the phone macro; this installer cannot claim the phone was updated",
    )
    return 0 if failures == 0 else 1


def parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", nargs="?", choices=("status", "enable", "disable"), help="read-only status, apply local differences, or restore owned local changes")
    parser.add_argument("--target-home", default=os.environ.get("TARGET_HOME", os.environ.get("HOME", "")), help="target home directory (default: TARGET_HOME or HOME)")
    parser.add_argument("--config-dir", default=os.environ.get("PHONE_TO_OMP_CONFIG_DIR"), help="private configuration directory")
    parser.add_argument("--state-dir", default=os.environ.get("STATE_DIR"), help="private ownership and restoration state directory")
    parser.add_argument("--python-command", dest="python", default=None)
    parser.add_argument("--tmux-command", dest="tmux", default=None)
    parser.add_argument("--tailscale-command", dest="tailscale", default=None)
    parser.add_argument("--systemctl-command", dest="systemctl", default=None)
    parser.add_argument("--ufw-command", dest="ufw", default=None)
    parser.add_argument("--sudo-command", dest="sudo", default=None)
    parser.add_argument("--phone", help="exact phone Tailscale DNS/host name or IPv4; required for enable")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"receiver TCP port (default: {DEFAULT_PORT})")
    parser.add_argument("--firewall", action="store_true", help="explicitly manage only the matching narrow UFW rule through sudo")
    parser.add_argument("--ack-policy", action="store_true", help="record that an administrator applied the exact generated grant; it does not test connectivity")
    return parser


def main() -> int:
    parsed = parser().parse_args()
    if not parsed.command:
        parser().print_help()
        return 0
    if not parsed.target_home:
        raise ProvisionError("TARGET_HOME/HOME is required")
    if parsed.ack_policy and parsed.command != "enable":
        raise ProvisionError("--ack-policy is only valid with enable")
    if not 1 <= parsed.port <= 65535:
        raise ProvisionError("--port must be in 1..65535")
    paths = paths_for(parsed)
    commands = commands_for(parsed)
    if parsed.command == "status":
        return status(parsed, paths, commands)
    if parsed.command == "enable":
        return enable(parsed, paths, commands)
    return disable(parsed, paths, commands)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProvisionError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2)
