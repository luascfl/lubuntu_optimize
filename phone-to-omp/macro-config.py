#!/usr/bin/env python3
"""Render a private MacroDroid import file from a sanitized JSON template."""

import argparse
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any
DEFAULT_TEMPLATE = Path(__file__).with_name("notification-template.mdr.json")
DEFAULT_CONFIG_DIR = Path.home() / ".config" / "phone-to-omp"
DEFAULT_REMOTE_PATH = "/sdcard/Download/phone-to-omp.mdr"
PLACEHOLDERS = {
    "__OMP_HOST__": "host",
    "__OMP_PORT__": "port",
    "__OMP_TOKEN__": "token",
}
PLACEHOLDER_PATTERN = re.compile(r"__OMP_[A-Za-z0-9_]+__")


class ConfigurationError(Exception):
    """Raised for an input that is unsuitable for safe rendering."""


def parser() -> argparse.ArgumentParser:
    argument_parser = argparse.ArgumentParser(
        description="Render a private MacroDroid JSON import from a sanitized template."
    )
    argument_parser.add_argument(
        "--template",
        type=Path,
        default=DEFAULT_TEMPLATE,
        help=f"sanitized MacroDroid JSON export (default: {DEFAULT_TEMPLATE})",
    )
    argument_parser.add_argument(
        "--output",
        required=True,
        type=Path,
        help="explicit private path for the rendered import file",
    )
    argument_parser.add_argument(
        "--config-dir",
        type=Path,
        default=DEFAULT_CONFIG_DIR,
        help=f"directory containing token and connection.json (default: {DEFAULT_CONFIG_DIR})",
    )
    argument_parser.add_argument(
        "--push",
        metavar="SERIAL",
        help="copy the rendered file to this ADB device serial after rendering",
    )
    argument_parser.add_argument(
        "--adb",
        default="adb",
        help="ADB executable for --push (default: adb)",
    )
    argument_parser.add_argument(
        "--remote-path",
        default=DEFAULT_REMOTE_PATH,
        help=f"device path for --push (default: {DEFAULT_REMOTE_PATH})",
    )
    return argument_parser


def private_regular_file(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise ConfigurationError(f"missing {label}: {path}") from error
    if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise ConfigurationError(f"{label} must be a regular file: {path}")
    if metadata.st_mode & 0o077:
        raise ConfigurationError(f"{label} must not be accessible to group or others: {path}")


def private_directory(path: Path, label: str) -> None:
    try:
        metadata = path.lstat()
    except FileNotFoundError as error:
        raise ConfigurationError(f"missing {label}: {path}") from error
    if not stat.S_ISDIR(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
        raise ConfigurationError(f"{label} must be a directory: {path}")
    if metadata.st_mode & 0o077:
        raise ConfigurationError(f"{label} must not be accessible to group or others: {path}")


def read_configuration(config_dir: Path) -> dict[str, str]:
    config_dir = config_dir.expanduser()
    private_directory(config_dir, "configuration directory")
    token_path = config_dir / "token"
    connection_path = config_dir / "connection.json"
    private_regular_file(token_path, "token file")
    private_regular_file(connection_path, "connection file")

    try:
        token = token_path.read_text(encoding="utf-8").strip()
    except UnicodeDecodeError as error:
        raise ConfigurationError("token file must be UTF-8 text") from error
    if not token:
        raise ConfigurationError("token file is empty")

    try:
        connection = json.loads(connection_path.read_text(encoding="utf-8"))
    except UnicodeDecodeError as error:
        raise ConfigurationError("connection file must be UTF-8 JSON") from error
    except json.JSONDecodeError as error:
        raise ConfigurationError(f"connection file is not valid JSON: {error.msg}") from error
    if not isinstance(connection, dict):
        raise ConfigurationError("connection file must contain an object")

    host = connection.get("host")
    phone_ip = connection.get("phone_ip")
    port = connection.get("port")
    if not isinstance(host, str) or not host or host.strip() != host or any(c.isspace() for c in host):
        raise ConfigurationError("connection host must be a non-empty whitespace-free string")
    if not isinstance(phone_ip, str) or not phone_ip or phone_ip.strip() != phone_ip or any(
        c.isspace() for c in phone_ip
    ):
        raise ConfigurationError("connection phone_ip must be a non-empty whitespace-free string")
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ConfigurationError("connection port must be an integer from 1 through 65535")

    return {"host": host, "port": str(port), "token": token}


def read_template(path: Path) -> Any:
    path = path.expanduser()
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise ConfigurationError(f"missing sanitized template: {path}") from error
    except IsADirectoryError as error:
        raise ConfigurationError(f"template must be a JSON file: {path}") from error
    except UnicodeDecodeError as error:
        raise ConfigurationError("template must be UTF-8 JSON") from error
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise ConfigurationError(f"template is not valid JSON: {error.msg}") from error


def collect_placeholders(value: Any, found: set[str]) -> None:
    if isinstance(value, str):
        found.update(PLACEHOLDER_PATTERN.findall(value))
    elif isinstance(value, list):
        for item in value:
            collect_placeholders(item, found)
    elif isinstance(value, dict):
        for item in value.values():
            collect_placeholders(item, found)


def render_value(value: Any, replacements: dict[str, str]) -> Any:
    if isinstance(value, str):
        for placeholder, replacement_name in PLACEHOLDERS.items():
            value = value.replace(placeholder, replacements[replacement_name])
        return value
    if isinstance(value, list):
        return [render_value(item, replacements) for item in value]
    if isinstance(value, dict):
        return {key: render_value(item, replacements) for key, item in value.items()}
    return value


def render(template: Any, replacements: dict[str, str]) -> bytes:
    found: set[str] = set()
    collect_placeholders(template, found)
    unexpected = found.difference(PLACEHOLDERS)
    missing = set(PLACEHOLDERS).difference(found)
    if unexpected:
        raise ConfigurationError("template contains unsupported OMP placeholder markers")
    if missing:
        raise ConfigurationError("template must contain __OMP_HOST__, __OMP_PORT__, and __OMP_TOKEN__")

    rendered = render_value(template, replacements)
    leftover: set[str] = set()
    collect_placeholders(rendered, leftover)
    if leftover:
        raise ConfigurationError("rendered output contains unresolved OMP placeholder markers")
    return (json.dumps(rendered, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def private_output_path(path: Path, template_path: Path) -> Path:
    output = path.expanduser()
    if not output.is_absolute():
        raise ConfigurationError("output path must be absolute and explicitly provided")
    if output.name in {"", ".", ".."}:
        raise ConfigurationError("output path must name a file")
    try:
        if output.resolve(strict=False) == template_path.expanduser().resolve(strict=False):
            raise ConfigurationError("output path must not overwrite the template")
    except OSError as error:
        raise ConfigurationError(f"cannot resolve output path: {output}") from error

    parent = output.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if parent.is_symlink():
        raise ConfigurationError(f"output directory must not be a symbolic link: {parent}")
    if not parent.is_dir():
        raise ConfigurationError(f"output parent is not a directory: {parent}")
    if stat.S_IMODE(parent.stat().st_mode) != 0o700:
        os.chmod(parent, 0o700)
    return output


def write_if_changed(path: Path, content: bytes) -> bool:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        metadata = None
    if metadata is not None:
        if not stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode):
            raise ConfigurationError(f"output must be a regular file: {path}")
        if path.read_bytes() == content:
            if metadata.st_mode & 0o077:
                os.chmod(path, 0o600)
            return False
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as temporary:
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    return True


def push_and_verify(adb: str, serial: str, local_path: Path, remote_path: str, content: bytes) -> None:
    if not remote_path.startswith("/"):
        raise ConfigurationError("remote path must be absolute")
    try:
        subprocess.run(
            [adb, "-s", serial, "push", str(local_path), remote_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        readback = subprocess.run(
            [adb, "-s", serial, "exec-out", "cat", remote_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
    except FileNotFoundError as error:
        raise ConfigurationError("ADB executable was not found") from error
    except subprocess.CalledProcessError as error:
        raise ConfigurationError("ADB push or readback failed") from error
    if readback != content:
        raise ConfigurationError("ADB readback did not exactly match the rendered file")


def main() -> int:
    arguments = parser().parse_args()
    try:
        template = read_template(arguments.template)
        replacements = read_configuration(arguments.config_dir)
        content = render(template, replacements)
        output = private_output_path(arguments.output, arguments.template)
        changed = write_if_changed(output, content)
        if arguments.push:
            push_and_verify(arguments.adb, arguments.push, output, arguments.remote_path, content)
    except (ConfigurationError, OSError) as error:
        print(f"macro-config: {error}", file=sys.stderr)
        return 1

    status = "rendered" if changed else "unchanged"
    print(f"macro-config: {status} private import file at {output}")
    if arguments.push:
        print("macro-config: copied to the connected phone; import, confirm any same-name replacement, and activate it in MacroDroid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
