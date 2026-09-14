#!/usr/bin/python3
"""Expose Dunst notification history from an IceWM tray icon."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from typing import Any

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk


DUNSTCTL = "dunstctl"
MAX_VISIBLE_NOTIFICATIONS = 10
REFRESH_SECONDS = 5

QTERMINAL_APP_NAMES = frozenset({"qterminal"})
QTERMINAL_WINDOW_CLASS = "qterminal.qterminal"


def run_dunstctl(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [DUNSTCTL, *args],
        check=False,
        text=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def activate_qterminal() -> bool:
    wmctrl = shutil.which("wmctrl")
    if wmctrl is None:
        return False

    return (
        subprocess.run(
            [wmctrl, "-xa", QTERMINAL_WINDOW_CLASS],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def compact(value: Any, limit: int = 72) -> str:
    text = " ".join(str(value or "").split())
    return text if len(text) <= limit else f"{text[: limit - 1]}…"


def unpack_dbus_value(value: Any) -> Any:
    if isinstance(value, dict):
        if set(value) == {"type", "data"}:
            return unpack_dbus_value(value["data"])
        return {key: unpack_dbus_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [unpack_dbus_value(item) for item in value]
    return value


class DunstTrayHistory:
    def __init__(self) -> None:
        self.icon = Gtk.StatusIcon.new_from_icon_name("dialog-information")
        self.icon.set_visible(True)
        self.icon.connect("activate", self.show_menu)
        self.icon.connect("popup-menu", self.show_menu)
        GLib.timeout_add_seconds(REFRESH_SECONDS, self.refresh)
        self.refresh()

    def history(self) -> list[dict[str, Any]]:
        result = run_dunstctl("history")
        if result.returncode != 0:
            print(f"dunstctl history failed: {result.stderr.strip()}", file=sys.stderr)
            return []
        try:
            entries = unpack_dbus_value(json.loads(result.stdout))
        except json.JSONDecodeError as error:
            print(f"dunst history is not valid JSON: {error}", file=sys.stderr)
            return []
        while isinstance(entries, list) and len(entries) == 1 and isinstance(entries[0], list):
            entries = entries[0]
        if not isinstance(entries, list):
            return []
        valid = [entry for entry in entries if isinstance(entry, dict) and isinstance(entry.get("id"), int)]
        return sorted(valid, key=lambda entry: entry["id"], reverse=True)

    def refresh(self) -> bool:
        count = len(self.history())
        self.icon.set_from_icon_name("mail-unread" if count else "mail-read")
        self.icon.set_tooltip_text(
            f"Notificações: {count}. Clique para abrir o histórico."
            if count
            else "Sem notificações pendentes."
        )
        return True

    def show_menu(self, *_args: object) -> None:
        menu = Gtk.Menu()
        entries = self.history()

        heading = Gtk.MenuItem(label=f"Notificações pendentes: {len(entries)}")
        heading.set_sensitive(False)
        menu.append(heading)
        menu.append(Gtk.SeparatorMenuItem())

        if entries:
            for entry in entries[:MAX_VISIBLE_NOTIFICATIONS]:
                self.add_notification_item(menu, entry)
            if len(entries) > MAX_VISIBLE_NOTIFICATIONS:
                remaining = Gtk.MenuItem(label=f"… e mais {len(entries) - MAX_VISIBLE_NOTIFICATIONS}")
                remaining.set_sensitive(False)
                menu.append(remaining)
        else:
            empty = Gtk.MenuItem(label="Nenhuma notificação no histórico")
            empty.set_sensitive(False)
            menu.append(empty)

        menu.append(Gtk.SeparatorMenuItem())
        clear = Gtk.MenuItem(label="Marcar todas como lidas")
        clear.set_sensitive(bool(entries))
        clear.connect("activate", self.clear_history)
        menu.append(clear)

        paused = run_dunstctl("is-paused").stdout.strip() == "true"
        dnd = Gtk.MenuItem(label="Desativar não perturbe" if paused else "Ativar não perturbe")
        dnd.connect("activate", self.toggle_dnd)
        menu.append(dnd)

        menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Encerrar indicador")
        quit_item.connect("activate", self.quit)
        menu.append(quit_item)

        menu.show_all()
        menu.popup_at_pointer(None)

    def add_notification_item(self, menu: Gtk.Menu, entry: dict[str, Any]) -> None:
        summary = compact(entry.get("summary") or entry.get("appname") or "Sem título")
        body = compact(entry.get("body"), limit=160)
        label = summary if not body else f"{summary}\n{body}"

        item = Gtk.MenuItem(label=label)
        item.connect("activate", self.open_notification, entry)
        menu.append(item)

    def open_notification(self, _item: Gtk.MenuItem, entry: dict[str, Any]) -> None:
        notification_id = entry["id"]
        match = re.search(r"https?://\S+", str(entry.get("urls", "")))
        appname = str(entry.get("appname") or "").casefold()

        if match:
            subprocess.Popen(
                ["xdg-open", match.group(0)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        elif appname not in QTERMINAL_APP_NAMES or not activate_qterminal():
            popped = run_dunstctl("history-pop", str(notification_id))
            if popped.returncode == 0:
                run_dunstctl("action")

        run_dunstctl("history-rm", str(notification_id))
        self.refresh()

    def clear_history(self, _item: Gtk.MenuItem) -> None:
        run_dunstctl("history-clear")
        self.refresh()

    def toggle_dnd(self, _item: Gtk.MenuItem) -> None:
        run_dunstctl("set-paused", "toggle")
        self.refresh()

    def quit(self, _item: Gtk.MenuItem) -> None:
        Gtk.main_quit()


def main() -> int:
    DunstTrayHistory()
    Gtk.main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
