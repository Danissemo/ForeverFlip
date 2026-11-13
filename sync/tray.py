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
    def __init__(self, icon_path: pathlib.Path, send):
        self.icon_path, self.send = icon_path, send
        self.icon = None
        self.told = False  # the "still running" notice is shown once a session

    def image(self):
        try:
            return Image.open(self.icon_path)
        except (OSError, ValueError):
            return Image.new('RGB', (64, 64), (38, 117, 241))

    def show(self, notice: str | None = None):
        """Puts the icon in the notification area (once)."""
        if not available() or self.icon is not None:
            return
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
            icon.run(setup=ready)
        threading.Thread(target=run, name='tray', daemon=True).start()

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
