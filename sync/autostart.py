"""Starting ForeverFlip Sync with Windows: a value in the user's own Run key (HKCU, no admin rights),
which starts the helper hidden in the tray. The key itself is the setting: what Windows will run is
what the switch shows, also after the entry was removed in Task Manager's Startup tab."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
NAME = "ForeverFlipSync"

try:
    import winreg
except ImportError:  # not Windows
    winreg = None


def available() -> bool:
    return winreg is not None and os.name == "nt"


def command(executable=None, script=None) -> str:
    """The command Windows runs at sign-in: the packaged helper, or pythonw with this script."""
    if executable is None and getattr(sys, "frozen", False):
        executable = sys.executable
    if executable is not None:
        parts = [str(pathlib.Path(executable).resolve())]
    else:
        python = pathlib.Path(sys.executable)
        windowless = python.with_name("pythonw.exe")  # no console window at sign-in
        script = script or pathlib.Path(__file__).resolve().with_name("foreverflip_sync.py")
        parts = [str(windowless if windowless.exists() else python), str(script)]
    return subprocess.list2cmdline(parts + ["--tray"])


def current() -> str | None:
    """The command registered now, None when there is none."""
    if not available():
        return None
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            value, _ = winreg.QueryValueEx(key, NAME)
            return str(value)
    except OSError:
        return None


def enabled() -> bool:
    return current() is not None


def enable(cmd: str | None = None) -> None:
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
        winreg.SetValueEx(key, NAME, 0, winreg.REG_SZ, cmd or command())


def disable() -> None:
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as key:
            winreg.DeleteValue(key, NAME)
    except FileNotFoundError:
        pass


def refresh() -> bool:
    """When it is on, points the entry at this helper (it may have been moved or replaced by an
    update). True when the entry was changed. Only the packaged helper does it: a run from the
    sources (development, tests) never takes the entry over from the installed one."""
    if not getattr(sys, "frozen", False):
        return False
    old = current()
    if old is None or old == command():
        return False
    enable()
    return True
