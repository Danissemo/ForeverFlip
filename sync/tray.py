"""The notification-area (tray) icon of ForeverFlip Sync: the window can close into it and the helper
keeps syncing and sharing scans in the background.

pystray runs the icon on a thread of its own. Its menu never touches Tk: each choice is handed to
`send` ("open", "sync" or "quit"), which the window reads from its event queue. Without pystray or
Pillow (a run from the sources without them) `available()` is False and the window closes as before.
"""

from __future__ import annotations

import pathlib
import threading

try:
    import pystray
    from PIL import Image
except ImportError:  # the packaged helper has both; a source run may not
    pystray = Image = None


def available() -> bool:
    return pystray is not None and Image is not None


class Tray:
    def __init__(self, icon_path, send):
        """`icon_path`: one image file or several to try in turn (the first that opens is used)."""
        paths = [icon_path] if isinstance(icon_path, (str, pathlib.Path)) else list(icon_path)
        self.icon_paths, self.send = [pathlib.Path(p) for p in paths], send
        self.icon = None
        self.told = False  # the "still running" notice is shown once a session

    def image(self):
        for path in self.icon_paths:
            try:
                image = Image.open(path)
                image.load()
                return image
            except (OSError, ValueError):
                continue
        return Image.new('RGB', (64, 64), (38, 117, 241))

    def show(self, notice: str | None = None) -> bool:
        """Puts the icon in the notification area (once); False when there is no icon to show, so the
        caller does not hide its window with nothing left to bring it back."""
        if not available():
            return False
        if self.icon is not None:
            return True
        try:
            return self._start(notice)
        except Exception:  # no notification area backend: the window must stay reachable
            self.icon = None
            return False

    def _start(self, notice):
        menu = pystray.Menu(
            pystray.MenuItem('Open ForeverFlip Sync', lambda: self.send('open'), default=True),
            pystray.MenuItem('Sync now', lambda: self.send('sync')),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem('Quit', lambda: self.send('quit')),
        )
        self.icon = pystray.Icon('ForeverFlipSync', self.image(), 'ForeverFlip Sync', menu)

        def run():
            icon = self.icon

            def ready(_icon):
                icon.visible = True
                if notice and not self.told:
                    self.told = True
                    try:
                        icon.notify(notice, 'ForeverFlip Sync')
                    except Exception:  # a notice is a courtesy; the icon works without it
                        pass
            try:
                icon.run(setup=ready)
            except Exception:
                if self.icon is icon:
                    self.icon = None
        threading.Thread(target=run, name='tray', daemon=True).start()
        return True

    def title(self, text: str):
        """The tooltip of the icon: the current status."""
        if self.icon is not None:
            try:
                self.icon.title = f'ForeverFlip Sync: {text}'[:127]
            except Exception:
                pass

    def hide(self):
        icon, self.icon = self.icon, None
        if icon is not None:
            try:
                icon.stop()
            except Exception:
                pass
