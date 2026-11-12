"""Small desktop front end. Tk owns the UI; one worker owns each sync operation.

The look follows the ForeverFlip Sync asset kit (sync/assets): a light blue window with soft waves,
the app's icon and name, the overall status on the right, and one white rounded card of settings
rows, each with its icon badge. The kit's PNGs (1x-4x, picked for the screen's scale) give the app
icon, badges, waves, button backgrounds and switches; whatever is missing is drawn by hand on
canvases instead. The hand-drawn widgets keep the ttk-style state()/instate() calls.
"""

from __future__ import annotations

import math
import os
import pathlib
import queue
import sys
import threading
import time
import tkinter as tk
import webbrowser
from tkinter import filedialog, font as tkfont, messagebox, ttk

import addon_update
import github_login
from game_location import AmbiguousGame, GameNotFound, normalize_game

SOURCES = {'helper': '', 'gh': ' (GitHub CLI)', 'environment': ' (FF_GITHUB_TOKEN)', 'config': ' (config.json)'}

# The kit's images; PyInstaller unpacks them under sys._MEIPASS/assets.
ASSETS = pathlib.Path(getattr(sys, '_MEIPASS', pathlib.Path(__file__).resolve().parent))/'assets'

# Colours of the asset kit's design tokens (sync/assets/tokens.json).
TOP = (245, 248, 255)  # window gradient, top
BOTTOM = (234, 242, 255)  # window gradient, bottom
WAVE = '#E4EDFE'
WAVE2 = '#EDF3FF'
CARD = '#FFFFFF'
CARD_LINE = '#BDCEFA'
SHADOW = '#E2EAF8'
DIVIDER = '#D3DFF6'
TEXT = '#07163D'
NAVY = '#07163D'
HINT = '#304879'
MUTED = '#304879'
FAINT = '#7B8BAA'
ACCENT = '#0066FF'
ACCENT_DARK = '#004CD5'
TILE = '#DEEAFF'
BUTTON = '#EBF2FF'
BUTTON_HOVER = '#E2EDFF'
BUTTON_LINE = '#ADC0E8'
TRACK_OFF = '#BCCBE5'
TONES = {'ok': '#16A34A', 'busy': ACCENT, 'warn': '#F08C1A', 'error': '#DC2626', 'idle': FAINT}


def hexcolor(rgb):
    return '#%02X%02X%02X' % tuple(int(round(c)) for c in rgb)


def blend(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Scale:
    """Pixel sizes of the mock-up (at 96 dpi) for this screen."""

    def __init__(self, root):
        self.k = max(1.0, root.winfo_fpixels('1i') / 96.0)

    def __call__(self, n):
        return int(round(n * self.k))


class Images:
    """The kit's PNGs at the density nearest this screen's scale, loaded once each.

    Tk cannot resample images, so the kit is kept at each common Windows scale: 1x-4x as delivered,
    1.25x/1.5x/1.75x/2.5x reduced from 4x. get() returns None when an image is missing or Tk cannot
    read it, so callers draw instead.
    """

    DENSITIES = (1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4)

    def __init__(self, root, scale, folder=ASSETS):
        self.root, self.folder = root, folder
        self.density = min(self.DENSITIES, key=lambda d: (abs(d - scale.k), -d))
        self.cache = {}

    def get(self, name, density=None):
        key = (name, density or self.density)
        if key not in self.cache:
            path = self.folder/f'{key[1]:g}x'/f'{name}.png'
            try:
                self.cache[key] = tk.PhotoImage(master=self.root, file=str(path)) if path.is_file() else None
            except tk.TclError:
                self.cache[key] = None
        return self.cache[key]

    def stretched(self, name, width):
        """A button background widened to `width`: both rounded ends kept, the middle column repeated."""
        key = (name, 'w', width)
        if key in self.cache:
            return self.cache[key]
        src = self.get(name)
        result = None
        if src is not None:
            sw, h = src.width(), src.height()
            cap = min(int(12 * self.density), sw // 2 - 1)
            width = max(width, 2 * cap + 1)
            result = tk.PhotoImage(master=self.root, width=width, height=h)
            copy = lambda *a: result.tk.call(result, 'copy', src, *a)  # noqa: E731 (tk's region copy)
            copy('-from', 0, 0, cap, h, '-to', 0, 0)
            copy('-from', cap, 0, cap + 1, h, '-to', cap, 0, width - cap, h)
            copy('-from', sw - cap, 0, sw, h, '-to', width - cap, 0)
        self.cache[key] = result
        return result


def window_icons(root, images):
    """Keep Tk on its PNG path: Tk 8.6's ICO reader expects DIB frames, not PNG frames."""
    icons = tuple(i for i in (images.get('app-icon', 1), images.get('app-icon', 2)) if i is not None)
    if not icons:
        icons = (app_icon_image(root, 32),)
    root.iconphoto(True, *icons)
    return icons


def fonts(root):
    families = set(tkfont.families(root))
    base = 'Segoe UI' if 'Segoe UI' in families else 'TkDefaultFont'
    semi = 'Segoe UI Semibold' if 'Segoe UI Semibold' in families else base
    return {
        'title': (base, 18, 'bold'),
        'subtitle': (base, 10),
        'status': (base, 10),
        'label': (base, 10, 'bold'),
        'body': (base, 11),
        'hint': (base, 10),
        'button': (base, 10),
        'switch': (base, 10),
        'foot': (base, 10),
        'code': ('Consolas', 18, 'bold'),
        'log': ('Consolas', 9),
    }


def rounded(canvas, x1, y1, x2, y2, r, fill='', outline='', width=1, tags=()):
    """A rounded rectangle from true quarter circles: a filled body, then its outline if any."""
    r = max(0.0, min(r, (x2 - x1) / 2, (y2 - y1) / 2))
    d = 2 * r
    if fill:
        canvas.create_rectangle(x1 + r, y1, x2 - r, y2, fill=fill, outline='', tags=tags)
        canvas.create_rectangle(x1, y1 + r, x2, y2 - r, fill=fill, outline='', tags=tags)
        for ax, ay in ((x1, y1), (x2 - d, y1), (x1, y2 - d), (x2 - d, y2 - d)):
            canvas.create_oval(ax, ay, ax + d, ay + d, fill=fill, outline='', tags=tags)
    if outline and outline != fill:
        for ax, ay, start in ((x1, y1, 90), (x2 - d, y1, 0), (x1, y2 - d, 180), (x2 - d, y2 - d, 270)):
            canvas.create_arc(ax, ay, ax + d, ay + d, start=start, extent=90, style='arc', outline=outline,
                              width=width, tags=tags)
        for a, b, c, e in ((x1 + r, y1, x2 - r, y1), (x1 + r, y2, x2 - r, y2), (x1, y1 + r, x1, y2 - r),
                           (x2, y1 + r, x2, y2 - r)):
            canvas.create_line(a, b, c, e, fill=outline, width=width, tags=tags)


# --- Icons: drawn around (cx, cy) in a box of size s ---------------------------------------------------

def icon(canvas, name, cx, cy, s, color, bg=TILE):
    w = max(1.5, s / 13)
    u = s / 24.0

    def P(x, y):
        return cx + (x - 12) * u, cy + (y - 12) * u

    if name == 'game':
        body = [P(7, 6.5), P(17, 6.5), P(20, 7.5), P(21.6, 11.5), P(22.2, 16.5), P(20.6, 18.8), P(18, 18.2),
                P(16, 15.4), P(8, 15.4), P(6, 18.2), P(3.4, 18.8), P(1.8, 16.5), P(2.4, 11.5), P(4, 7.5)]
        canvas.create_polygon([c for p in body for c in p], smooth=True, splinesteps=12, outline=color, fill=bg,
                              width=w)
        canvas.create_line(*P(7.5, 9.2), *P(7.5, 13.6), fill=color, width=w, capstyle='round')
        canvas.create_line(*P(5.3, 11.4), *P(9.7, 11.4), fill=color, width=w, capstyle='round')
        for x, y in ((15.8, 10.2), (18, 12.4)):
            canvas.create_oval(*P(x - 1.1, y - 1.1), *P(x + 1.1, y + 1.1), fill=color, outline=color)
    elif name == 'github':
        canvas.create_oval(*P(2, 2), *P(22, 22), fill=color, outline=color)
        # the cat: head with ears, a narrow body down to the bottom edge
        head = [P(7, 9.4), P(6.6, 6.2), P(9.2, 7.5), P(12, 7.1), P(14.8, 7.5), P(17.4, 6.2), P(17, 9.4),
                P(17.8, 11.4), P(16.6, 14.2), P(14.2, 15.2), P(14.5, 21.5), P(9.5, 21.5), P(9.8, 15.2),
                P(7.4, 14.2), P(6.2, 11.4)]
        canvas.create_polygon([c for p in head for c in p], smooth=True, splinesteps=12, fill=bg, outline=bg)
        canvas.create_line(*P(9.8, 17.2), *P(7.6, 16.6), *P(6.6, 15.6), fill=bg, width=w * 0.9, smooth=True)
    elif name == 'share':
        a, b, c = P(17.5, 5.5), P(6.5, 12), P(17.5, 18.5)
        canvas.create_line(*a, *b, fill=color, width=w)
        canvas.create_line(*b, *c, fill=color, width=w)
        for x, y in (a, b, c):
            canvas.create_oval(x - 3 * u, y - 3 * u, x + 3 * u, y + 3 * u, outline=color, fill=bg, width=w)
    elif name == 'puzzle':
        body = [P(4, 8), P(8.5, 8), P(8.5, 6.6), P(9, 5), P(10.5, 4), P(12, 4), P(13.5, 5), P(14, 6.6),
                P(14, 8), P(18, 8), P(18, 12), P(19.4, 12), P(21, 12.6), P(21.6, 14.2), P(21, 15.8),
                P(19.4, 16.4), P(18, 16.4), P(18, 20.5), P(13.6, 20.5), P(13.6, 19), P(12.8, 17.6), P(11, 17.2),
                P(9.2, 17.6), P(8.4, 19), P(8.4, 20.5), P(4, 20.5)]
        canvas.create_polygon([c for p in body for c in p], outline=color, fill=bg, width=w, joinstyle='round')
    elif name == 'database':
        canvas.create_oval(*P(4.5, 3.5), *P(19.5, 8.5), outline=color, width=w)
        canvas.create_line(*P(4.5, 6), *P(4.5, 18), fill=color, width=w)
        canvas.create_line(*P(19.5, 6), *P(19.5, 18), fill=color, width=w)
        for y in (12, 18):
            canvas.create_arc(*P(4.5, y - 2.5), *P(19.5, y + 2.5), start=180, extent=180, style='arc',
                              outline=color, width=w)
    elif name == 'info':
        canvas.create_oval(*P(2.5, 2.5), *P(21.5, 21.5), outline=color, width=w)
        canvas.create_line(*P(12, 10.5), *P(12, 17), fill=color, width=w * 1.2, capstyle='round')
        canvas.create_oval(*P(11, 6.4), *P(13, 8.4), fill=color, outline=color)
    elif name == 'chevron':
        canvas.create_line(*P(9, 5), *P(16, 12), *P(9, 19), fill=color, width=w * 1.2, capstyle='round',
                           joinstyle='round')
    elif name == 'check':
        canvas.create_oval(*P(2.5, 2.5), *P(21.5, 21.5), fill=color, outline=color)
        canvas.create_line(*P(7.5, 12.5), *P(10.5, 15.5), *P(16.5, 9), fill='#FFFFFF', width=w * 1.3,
                           capstyle='round', joinstyle='round')
    elif name == 'alert':
        canvas.create_oval(*P(2.5, 2.5), *P(21.5, 21.5), fill=color, outline=color)
        canvas.create_line(*P(12, 7), *P(12, 13.5), fill='#FFFFFF', width=w * 1.3, capstyle='round')
        canvas.create_oval(*P(11, 16), *P(13, 18), fill='#FFFFFF', outline='#FFFFFF')
    elif name == 'ring':
        canvas.create_oval(*P(4, 4), *P(20, 20), outline=color, width=w * 1.3)
        canvas.create_arc(*P(4, 4), *P(20, 20), start=90, extent=110, style='arc', outline=bg, width=w * 1.6)
    elif name == 'feather':
        # a white quill leaning right: a broad vane, a blue spine, a white stem
        vane = [P(21, 1.8), P(14, 3.6), P(9, 7.6), P(6.2, 12.6), P(5.4, 18.4), P(9.6, 16.8), P(14.6, 13.8),
                P(18.4, 9.4), P(20.6, 4.8)]
        canvas.create_polygon([c for p in vane for c in p], smooth=True, splinesteps=16, fill='#FFFFFF',
                              outline='#FFFFFF')
        canvas.create_line(*P(19.6, 3.4), *P(12.5, 10.5), *P(6.4, 17.6), fill=color, width=w * 0.8, smooth=True,
                           capstyle='round')
        canvas.create_line(*P(6.8, 17.2), *P(3, 21.6), fill='#FFFFFF', width=w * 1.3, capstyle='round')


def app_icon_image(root, size=32):
    """The window icon: a blue rounded square with a white quill, rasterised pixel by pixel."""
    img = tk.PhotoImage(width=size, height=size)
    r = size * 0.22
    rows = []
    for y in range(size):
        row = []
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx = max(r - px, 0, px - (size - r))
            dy = max(r - py, 0, py - (size - r))
            if dx * dx + dy * dy > r * r:
                row.append('#F6F9FE')  # PhotoImage.put has no transparency: the window's colour
                continue
            colour = hexcolor(blend((54, 135, 255), (24, 92, 214), (px + py) / (2 * size)))
            # the quill: a leaf along the diagonal, as an ellipse in rotated coordinates
            u, v = (px - size * 0.52) / size, (py - size * 0.48) / size
            a = math.radians(45)
            ru, rv = u * math.cos(a) - v * math.sin(a), u * math.sin(a) + v * math.cos(a)
            if (rv / 0.36) ** 2 + (ru / 0.13) ** 2 <= 1 and rv < 0.32:
                colour = '#FFFFFF'
            row.append(colour)
        rows.append('{' + ' '.join(row) + '}')
    img.put(' '.join(rows))
    return img


# --- Hand-drawn widgets ---------------------------------------------------------------------------

class Widget:
    """The ttk-style state()/instate() pair for the hand-drawn widgets (only "disabled")."""

    disabled = False

    def state(self, flags=None):
        if flags:
            for flag in flags:
                if flag == 'disabled':
                    self.disabled = True
                elif flag == '!disabled':
                    self.disabled = False
            self.redraw()
        return ('disabled',) if self.disabled else ()

    def instate(self, flags):
        return all(self.disabled if f == 'disabled' else not self.disabled for f in flags if f in ('disabled', '!disabled'))


class RoundButton(Widget, tk.Canvas):
    """A rounded button: light blue fill, blue outline; "accent" text is blue (Change)."""

    def __init__(self, master, text, command, font, scale, accent=False, bg=CARD, width=None, images=None):
        self.text, self.command, self.font, self.accent, self.s = text, command, font, accent, scale
        self.images = images
        self.hover = self.pressed = False
        self.fixed = width
        tk.Canvas.__init__(self, master, bg=bg, highlightthickness=0, bd=0, cursor='hand2')
        self.bind('<Enter>', lambda _: self.set_hover(True))
        self.bind('<Leave>', lambda _: self.set_hover(False))
        self.bind('<ButtonPress-1>', self.press)
        self.bind('<ButtonRelease-1>', self.click)
        self.redraw()

    def set_hover(self, value):
        self.hover = value
        if not value:
            self.pressed = False
        self.redraw()

    def press(self, _event=None):
        self.pressed = not self.disabled
        self.redraw()

    def click(self, event=None):
        """A mouse release counts only over the button that was pressed; a direct call always does."""
        was_pressed, self.pressed = self.pressed, False
        self.redraw()
        if (event is None or (was_pressed and self.hover)) and not self.disabled and self.command:
            self.command()

    def configure(self, cnf=None, **kw):
        if 'text' in kw:
            self.text = kw.pop('text')
            self.redraw()
        if kw or cnf:
            return tk.Canvas.configure(self, cnf, **kw)

    config = configure

    def cget(self, key):
        return self.text if key == 'text' else tk.Canvas.cget(self, key)

    def redraw(self):
        s = self.s
        f = tkfont.Font(font=self.font)
        w = max(self.fixed or s(106), f.measure(self.text) + s(36))
        state = 'disabled' if self.disabled else 'pressed' if self.pressed else 'hover' if self.hover else 'default'
        image = self.images.stretched(f'button-{state}', w) if self.images else None
        h = image.height() if image else s(32)
        tk.Canvas.configure(self, width=w, height=h)
        self.delete('all')
        if image:
            self.create_image(0, 0, image=image, anchor='nw')
        else:
            fill = BUTTON_HOVER if self.hover and not self.disabled else BUTTON
            line = BUTTON_LINE if not self.disabled else '#CFD8E9'
            rounded(self, 1, 1, w - 1, h - 1, s(7), fill='#EEF2F9' if self.disabled else fill, outline=line, width=1)
        colour = FAINT if self.disabled else ACCENT if self.accent else TEXT
        self.create_text(w / 2, h / 2, text=self.text, font=self.font, fill=colour)
        tk.Canvas.configure(self, cursor='arrow' if self.disabled else 'hand2')


class Switch(Widget, tk.Frame):
    """A pill switch with its label, bound to a BooleanVar."""

    def __init__(self, master, text, variable, command, font, scale, bg=CARD, images=None):
        tk.Frame.__init__(self, master, bg=bg)
        self.variable, self.command, self.s, self.images = variable, command, scale, images
        self.hover = self.pressed = False
        sample = images.get('switch-off-default') if images else None
        self.W, self.H = (sample.width(), sample.height()) if sample else (scale(40), scale(21))
        self.canvas = tk.Canvas(self, width=self.W, height=self.H, bg=bg, highlightthickness=0, bd=0, cursor='hand2')
        self.canvas.pack(side='left')
        self.label = tk.Label(self, text=text, bg=bg, fg=TEXT, font=font, cursor='hand2', padx=scale(10))
        self.label.pack(side='left')
        for widget in (self.canvas, self.label):
            widget.bind('<ButtonPress-1>', self.press)
            widget.bind('<ButtonRelease-1>', self.toggle)
            widget.bind('<Enter>', lambda _: self.set_hover(True))
            widget.bind('<Leave>', lambda _: self.set_hover(False))
        variable.trace_add('write', lambda *_: self.redraw())
        self.redraw()

    def set_hover(self, value):
        self.hover = value
        self.redraw()

    def press(self, _event=None):
        self.pressed = not self.disabled
        self.redraw()

    def toggle(self, _event=None):
        self.pressed = False
        if self.disabled:
            self.redraw()
            return
        self.variable.set(not self.variable.get())
        if self.command:
            self.command()

    def redraw(self):
        on = bool(self.variable.get())
        c, w, h = self.canvas, self.W, self.H
        c.delete('all')
        state = 'disabled' if self.disabled else 'pressed' if self.pressed else 'hover' if self.hover else 'default'
        image = self.images.get(f'switch-{"on" if on else "off"}-{state}') if self.images else None
        if image:
            c.create_image(0, 0, image=image, anchor='nw')
        else:
            track = (('#9CBBED' if on else '#D9E1EF') if self.disabled else (ACCENT if on else TRACK_OFF))
            rounded(c, 0, 0, w, h, h / 2, fill=track, outline=track)
            knob = h - self.s(5)
            x = w - knob - self.s(2.5) if on else self.s(2.5)
            c.create_oval(x, self.s(2.5), x + knob, self.s(2.5) + knob, fill='#FFFFFF', outline='#FFFFFF')
        self.label.configure(fg=FAINT if self.disabled else TEXT)
        cursor = 'arrow' if self.disabled else 'hand2'
        c.configure(cursor=cursor)
        self.label.configure(cursor=cursor)


class LinkButton(Widget, tk.Label):
    def __init__(self, master, text, command, font, bg):
        tk.Label.__init__(self, master, text=text, font=font, bg=bg, fg=ACCENT, cursor='hand2', bd=0)
        self.command = command
        self.bind('<ButtonRelease-1>', lambda _: (not self.disabled and self.command and self.command()))
        self.bind('<Enter>', lambda _: self.configure(fg=ACCENT_DARK if not self.disabled else FAINT))
        self.bind('<Leave>', lambda _: self.redraw())

    def redraw(self):
        self.configure(fg=FAINT if self.disabled else ACCENT, cursor='arrow' if self.disabled else 'hand2')


class ActivityBar(tk.Canvas):
    """A thin moving bar while something runs; empty otherwise."""

    def __init__(self, master, bg):
        super().__init__(master, height=3, bg=bg, highlightthickness=0, bd=0)
        self.running, self.x = False, 0

    def start(self):
        if not self.running:
            self.running = True
            self.tick()

    def stop(self):
        self.running = False
        self.delete('all')

    def tick(self):
        if not self.running:
            return
        width = max(self.winfo_width(), 1)
        self.x = (self.x + 6) % (width + 160)
        self.delete('all')
        self.create_rectangle(self.x - 160, 0, self.x, 3, fill=ACCENT, outline='')
        self.after(16, self.tick)


def shorten(path: str, limit: int = 46) -> str:
    return path if len(path) <= limit else path[:16] + '…' + path[-(limit - 17):]


class SyncWindow:
    def __init__(self, root, args, config, folder, core):
        self.root, self.args, self.config, self.folder, self.core = root, args, config, folder, core
        self.events = queue.Queue()
        self.game = self.session = None
        self.busy = self.closing = False
        self.next_check = 0.0
        self.account = None  # (login, source) once signed in to GitHub
        self.login_running = self.login_cancel = False
        self.account_text = tk.StringVar(value='Checking the GitHub sign-in…')
        self.updating = False
        self.next_update = 0.0
        self.addon_release = None  # a newer release found and not installed
        self.addon_text = tk.StringVar(value='Checking for updates…')
        self.update_auto = tk.BooleanVar(value=config.get('update_addon', True))
        self.beta = tk.BooleanVar(value=config.get('beta', False))
        self.auto = tk.BooleanVar(value=not args.paused and config.get('automatic', True))
        self.share = tk.BooleanVar(value=not args.download_only and (args.upload or bool(config.get('upload', False))))
        self.status = tk.StringVar(value='Finding your Forever installation…')
        self.last_sync = tk.StringVar(value='Not synced yet')
        self.path = tk.StringVar()
        self.path_text = tk.StringVar(value='Looking for WoW Forever…')
        self.share_hint = tk.StringVar()
        self.code_text = tk.StringVar()
        self.log_open = False
        self.tone_name = 'idle'
        s = self.s = Scale(root)
        f = self.f = fonts(root)
        img = self.img = Images(root, s)

        root.title('ForeverFlip Sync')
        root.configure(bg=hexcolor(BOTTOM))
        root.protocol('WM_DELETE_WINDOW', self.close)
        try:
            self.icon_images = window_icons(root, img)
            self.icon_image = self.icon_images[0]
        except tk.TclError:
            pass
        self.width = s(664)
        root.geometry(f'{self.width}x{s(600)}')
        root.minsize(s(620), s(400))

        # The background: gradient and waves; the header and the card are drawn on it.
        self.bg = tk.Canvas(root, highlightthickness=0, bd=0)
        self.bg.pack(fill='both', expand=True)
        self.bg.bind('<Configure>', lambda _: self.layout())

        self.progress = ActivityBar(self.bg, hexcolor(TOP))
        self.progress_item = self.bg.create_window(0, 0, anchor='nw', window=self.progress)

        # The card's content: a white frame inside the rounded card.
        self.inner = tk.Frame(self.bg, bg=CARD)
        self.inner_item = self.bg.create_window(0, 0, anchor='nw', window=self.inner)
        self.inner.columnconfigure(3, weight=1)
        self.inner.bind('<Configure>', lambda _: self.layout())
        self.row_count = 0

        game = self.row('game', 'Game')
        tk.Label(game, textvariable=self.path_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(side='left')
        self.locations = ttk.Combobox(game, textvariable=self.path, state='readonly', width=40)
        self.locations.bind('<<ComboboxSelected>>', lambda _: self.select_game(self.path.get()))
        self.choose_button = RoundButton(self.actions, 'Change', self.choose_game, f['button'], s, accent=True,
                                         width=s(106), images=img)
        self.choose_button.pack(side='right')

        github = self.row('github', 'GitHub')
        tk.Label(github, textvariable=self.account_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        self.code_box = tk.Frame(github, bg=TILE, padx=s(14), pady=s(8))
        tk.Label(self.code_box, textvariable=self.code_text, font=f['code'], bg=TILE, fg=ACCENT).pack(anchor='w')
        tk.Label(self.code_box, text='Copied. Paste it on the page that opened and approve ForeverFlip Sync.',
                 font=f['hint'], bg=TILE, fg=HINT, justify='left', wraplength=s(300)).pack(anchor='w')
        self.login_button = RoundButton(self.actions, 'Sign in with GitHub', self.sign_in_or_out, f['button'], s,
                                        width=s(106), images=img)
        self.login_button.pack(side='right')

        sharing = self.row('share', 'Sharing')
        self.share_button = Switch(sharing, 'Share my full scans', self.share, self.options_changed, f['body'], s, images=img)
        self.share_button.pack(anchor='w')
        tk.Label(sharing, textvariable=self.share_hint, font=f['hint'], bg=CARD, fg=HINT, anchor='w',
                 justify='left', wraplength=s(320)).pack(anchor='w', pady=(s(6), 0))

        addon = self.row('puzzle', 'Addon')
        tk.Label(addon, textvariable=self.addon_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        toggles = tk.Frame(addon, bg=CARD)
        toggles.pack(anchor='w', pady=(s(10), 0))
        Switch(toggles, 'Install updates', self.update_auto, self.addon_options_changed, f['switch'], s, images=img).pack(side='left')
        Switch(toggles, 'Beta tester', self.beta, self.addon_options_changed, f['switch'], s, images=img).pack(
            side='left', padx=(s(28), 0))
        self.update_button = RoundButton(self.actions, 'Update', lambda: self.start_update(install=True), f['button'],
                                         s, width=s(106), images=img)
        self.update_button.pack(side='right')
        self.update_button.state(['disabled'])

        prices = self.row('database', 'Prices', last=True)
        tk.Label(prices, textvariable=self.last_sync, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        self.auto_button = Switch(prices, 'Sync automatically', self.auto, self.options_changed, f['switch'], s, images=img)
        self.auto_button.pack(anchor='w', pady=(s(10), 0))
        self.sync_button = RoundButton(self.actions, 'Sync now', lambda: self.start_sync(force=True), f['button'], s,
                                       width=s(106), images=img)
        self.sync_button.pack(side='right')
        self.sync_button.state(['disabled'])

        # Footer: the in-game step, and the activity log behind a link.
        self.foot = tk.Frame(self.bg, bg=hexcolor(BOTTOM))
        self.foot_item = self.bg.create_window(0, 0, anchor='nw', window=self.foot)
        info = self.picture(self.foot, 'info', s(22), hexcolor(BOTTOM),
                            lambda c, n: icon(c, 'info', n / 2, n / 2, n, ACCENT, hexcolor(BOTTOM)))
        info.pack(side='left', padx=(0, s(8)))
        tk.Label(self.foot, text='After a sync, type /reload in game to read the new prices.', font=f['foot'],
                 bg=hexcolor(BOTTOM), fg=TEXT).pack(side='left')
        self.chevron = self.picture(self.foot, 'chevron-right', s(16), hexcolor(BOTTOM),
                                    lambda c, n: icon(c, 'chevron', n / 2, n / 2, n, ACCENT, hexcolor(BOTTOM)),
                                    cursor='hand2')
        self.chevron.pack(side='right', padx=(s(2), 0))
        self.chevron.bind('<ButtonRelease-1>', lambda _: self.toggle_log())
        self.log_button = LinkButton(self.foot, 'Show activity', self.toggle_log, f['foot'], hexcolor(BOTTOM))
        self.log_button.pack(side='right')

        self.log_frame = tk.Frame(self.bg, bg=CARD, highlightthickness=1, highlightbackground=CARD_LINE)
        self.output = tk.Text(self.log_frame, width=1, height=8, wrap='word', state='disabled', font=f['log'],
                              relief='flat', bg=CARD, fg=MUTED, bd=0, padx=s(14), pady=s(10), highlightthickness=0)
        scroll = ttk.Scrollbar(self.log_frame, command=self.output.yview)
        self.output.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.output.pack(side='left', fill='both', expand=True)
        self.log_item = None

        self.refresh_share_state()
        core.LOG_SINK = lambda line: self.events.put(('log', line))
        self.set_busy(True)
        self.status.trace_add('write', lambda *_: self.draw_status())
        self.layout()
        root.after(50, self.discover)
        root.after(60, self.check_account)
        root.after(100, self.poll)

    # --- Drawing ----------------------------------------------------------------------------------

    def row(self, glyph, title, last=False):
        """A settings row: icon tile, title, a vertical rule, a content frame (returned), self.actions."""
        s, f = self.s, self.f
        r = 2 * self.row_count
        self.row_count += 1
        pad = (s(14), s(14))
        badge = {'game': 'badge-game', 'github': 'badge-github', 'share': 'badge-sharing', 'puzzle': 'badge-addon',
                 'database': 'badge-prices'}[glyph]
        tile = self.picture(self.inner, badge, s(32), CARD, lambda c, n: (
            rounded(c, 0, 0, n, n, s(8), fill=TILE, outline=TILE), icon(c, glyph, n / 2, n / 2, s(22), ACCENT, TILE)))
        tile.grid(row=r, column=0, sticky='nw', padx=(s(17), s(13)), pady=pad)
        tk.Label(self.inner, text=title.upper(), font=f['label'], bg=CARD, fg=NAVY, anchor='w', width=8).grid(
            row=r, column=1, sticky='nw', pady=(s(19), s(14)))
        rule = tk.Frame(self.inner, bg=DIVIDER, width=1)
        rule.grid(row=r, column=2, sticky='ns', padx=(s(8), s(20)), pady=pad)
        content = tk.Frame(self.inner, bg=CARD)
        content.grid(row=r, column=3, sticky='ew', pady=(s(18), s(14)))
        self.actions = tk.Frame(self.inner, bg=CARD)
        self.actions.grid(row=r, column=4, sticky='ne', padx=(s(12), s(14)), pady=(s(14), s(14)))
        if not last:
            tk.Frame(self.inner, bg=DIVIDER, height=1).grid(row=r + 1, column=0, columnspan=5, sticky='ew',
                                                            padx=(s(17), s(14)))
        return content

    def picture(self, parent, name, size, bg, draw, cursor=''):
        """A canvas showing one of the kit's images, or `draw(canvas, size)` when the image is missing."""
        image = self.img.get(name)
        w, h = (image.width(), image.height()) if image else (size, size)
        canvas = tk.Canvas(parent, width=w, height=h, bg=bg, highlightthickness=0, bd=0, cursor=cursor)
        if image:
            canvas.create_image(0, 0, image=image, anchor='nw')
        else:
            draw(canvas, size)
        return canvas

    def draw_background(self, w, h):
        c, s = self.bg, self.s
        c.delete('backdrop')
        bands = 48
        for i in range(bands):
            y1, y2 = h * i / bands, h * (i + 1) / bands + 1
            c.create_rectangle(0, y1, w, y2, fill=hexcolor(blend(TOP, BOTTOM, i / bands)), outline='', tags='backdrop')
        # soft waves in the top right corner: the kit's layer (drawn under a 34 px title bar in the kit)
        waves = self.img.get('header-waves')
        if waves:
            c.create_image(w, -s(34), image=waves, anchor='ne', tags='backdrop')
        else:
            for colour, dy in ((WAVE2, s(10)), (WAVE, s(0))):
                pts = [w * 0.48, 0, w * 0.6, s(28) + dy, w * 0.72, s(46) + dy, w * 0.86, s(30) + dy, w, s(70) + dy,
                       w, 0]
                c.create_polygon(pts, smooth=True, splinesteps=24, fill=colour, outline='', tags='backdrop')
            pts = [w * 0.62, s(150), w * 0.78, s(118), w * 0.9, s(150), w, s(126), w, s(170), w * 0.6, s(176)]
            c.create_polygon(pts, smooth=True, splinesteps=24, fill=WAVE2, outline='', tags='backdrop')
        c.tag_lower('backdrop')

    # The header of the kit: a 48 px app icon at (27, 24), the title 18 px to its right.
    HEADER_X, HEADER_Y, HEADER_ICON, HEADER_GAP = 27, 24, 48, 18

    def title_end(self):
        s, f = self.s, self.f
        return s(self.HEADER_X + self.HEADER_ICON + self.HEADER_GAP) + max(
            tkfont.Font(font=f['title']).measure('ForeverFlip Sync'),
            tkfont.Font(font=f['subtitle']).measure('Community prices and addon updates for WoW Forever'))

    def draw_header(self, w):
        c, s, f = self.bg, self.s, self.f
        c.delete('header')
        x, y = s(self.HEADER_X), s(self.HEADER_Y)
        size = s(self.HEADER_ICON)
        tx = x + size + s(self.HEADER_GAP)
        logo = self.img.get('app-icon')
        if logo:
            c.create_image(x + size / 2, y + size / 2, image=logo, anchor='center', tags='header')
        else:
            self.draw_app_icon(x, y, size)
        c.create_text(tx, y - s(6), text='ForeverFlip Sync', font=f['title'], fill=NAVY, anchor='nw', tags='header')
        c.create_text(tx, y + s(31), text='Community prices and addon updates for WoW Forever', font=f['subtitle'],
                      fill=MUTED, anchor='nw', tags='header')
        self.draw_status()

    def draw_app_icon(self, x, y, size):
        """The app icon drawn by hand, for when the kit's image is missing."""
        c, s = self.bg, self.s
        r = size * 0.22
        rounded(c, x, y, x + size, y + size, r, fill='#2675F1', tags='header')
        for i in range(size - 2 * r):  # the gradient between the rounded ends
            colour = hexcolor(blend((58, 140, 255), (26, 98, 222), i / max(1, size - 2 * r)))
            c.create_line(x, y + r + i, x + size, y + r + i, fill=colour, tags='header')
        c.create_rectangle(x + r, y, x + size - r, y + r, fill='#3A8CFF', outline='', tags='header')
        c.create_oval(x, y, x + 2 * r, y + 2 * r, fill='#3A8CFF', outline='', tags='header')
        c.create_oval(x + size - 2 * r, y, x + size, y + 2 * r, fill='#3A8CFF', outline='', tags='header')
        c.create_rectangle(x + r, y + size - r, x + size - r, y + size, fill='#1A62DE', outline='', tags='header')
        c.create_oval(x, y + size - 2 * r, x + 2 * r, y + size, fill='#1A62DE', outline='', tags='header')
        c.create_oval(x + size - 2 * r, y + size - 2 * r, x + size, y + size, fill='#1A62DE', outline='',
                      tags='header')
        before = set(c.find_all())
        icon(c, 'feather', x + size / 2, y + size / 2, size * 0.69, '#2675F1', '#2675F1')
        for item in set(c.find_all()) - before:
            c.addtag_withtag('header', item)

    def draw_status(self):
        c, s, f = self.bg, self.s, self.f
        w = max(self.bg.winfo_width(), self.width)
        c.delete('status')
        text = self.status.get()
        font = tkfont.Font(font=f['status'])
        width = min(font.measure(text), s(240))
        right = w - s(22)
        tx = right - width
        cy = s(self.HEADER_Y + self.HEADER_ICON / 2)
        icon_x = tx - s(20)
        rule_x = icon_x - s(26)
        if rule_x > self.title_end() + s(12):
            c.create_line(rule_x, cy - s(18), rule_x, cy + s(18), fill=DIVIDER, tags='status')
        tone = TONES.get(self.tone_name, FAINT)
        before = set(c.find_all())
        glyph = {'ok': 'check', 'busy': 'ring', 'error': 'alert', 'idle': 'ring'}.get(self.tone_name, 'alert')
        if self.tone_name == 'warn' and 'GitHub' in text:
            glyph = 'github'
        icon(c, glyph, icon_x, cy, s(24), tone, hexcolor(TOP))
        for item in set(c.find_all()) - before:
            c.addtag_withtag('status', item)
        c.create_text(tx, cy, text=text, font=f['status'], fill=TEXT, anchor='w', width=s(240), tags='status')

    def layout(self):
        c, s = self.bg, self.s
        self.inner.update_idletasks()
        margin = s(22)  # the kit's panel: x 22, y 100 under the title bar, radius 11
        need = self.inner.winfo_reqwidth() + 2 * margin + s(12)
        w = max(c.winfo_width(), need)
        card_top = s(100)
        card_w = w - 2 * margin
        inner_pad = s(6)
        inner_h = self.inner.winfo_reqheight()
        card_h = inner_h + 2 * inner_pad
        c.delete('card')
        rounded(c, margin + 1, card_top + s(3), margin + card_w + 1, card_top + card_h + s(4), s(11), fill=SHADOW,
                outline=SHADOW, tags='card')
        rounded(c, margin, card_top, margin + card_w, card_top + card_h, s(11), fill=CARD, outline=CARD_LINE,
                tags='card')
        c.coords(self.inner_item, margin + inner_pad, card_top + inner_pad)
        c.itemconfigure(self.inner_item, width=card_w - 2 * inner_pad)
        c.coords(self.progress_item, margin + s(16), card_top - s(10))
        c.itemconfigure(self.progress_item, width=card_w - s(32))
        foot_y = card_top + card_h + s(22)
        c.coords(self.foot_item, margin + s(14), foot_y)
        c.itemconfigure(self.foot_item, width=card_w - s(24))
        bottom = foot_y + self.foot.winfo_reqheight()
        if self.log_open:
            if self.log_item is None:
                self.log_item = c.create_window(0, 0, anchor='nw', window=self.log_frame)
            # never taller than the screen: the log gives way first
            room = self.root.winfo_screenheight() - s(110) - (bottom + s(14) + s(28))
            log_h = max(s(56), min(s(170), room))
            c.coords(self.log_item, margin, bottom + s(14))
            c.itemconfigure(self.log_item, width=card_w, height=log_h)
            bottom += s(14) + log_h
        elif self.log_item is not None:
            c.delete(self.log_item)
            self.log_item = None
        height = bottom + s(28)
        h = max(c.winfo_height(), height)
        self.draw_background(w, h)
        self.draw_header(w)
        c.tag_raise('card')
        c.tag_raise('header')
        c.tag_raise('status')
        width = max(self.root.winfo_width() if self.root.winfo_ismapped() else self.width, need)
        if abs(self.root.winfo_height() - height) > 2 or self.root.winfo_width() < need or \
                not self.root.winfo_ismapped():
            self.root.geometry(f'{width}x{height}')
        self.root.minsize(need, height)

    def tone(self, name):
        self.tone_name = name
        self.draw_status()

    def toggle_log(self):
        self.log_open = not self.log_open
        self.log_button.configure(text='Hide activity' if self.log_open else 'Show activity')
        self.layout()

    def set_busy(self, value):
        self.busy = value
        self.choose_button.state(['disabled'] if value else ['!disabled'])
        self.refresh_share_state()
        self.locations.configure(state='disabled' if value else 'readonly')
        self.sync_button.state(['disabled'] if value or not self.game else ['!disabled'])
        if value:
            self.progress.start()
            self.tone('busy')
        else:
            self.progress.stop()

    # --- Addon updates ----------------------------------------------------------------------------

    def addon_options_changed(self):
        self.config['update_addon'], self.config['beta'] = self.update_auto.get(), self.beta.get()
        try:
            self.core.save_json(self.folder/'config.json', self.config)
        except OSError as error:
            self.status.set(f'Could not save options: {error}')
        self.next_update = 0.0  # look again at once: the beta choice changes what is offered

    def start_update(self, install=None):
        """Looks for a newer release; installs it when asked or when updates are automatic."""
        if self.updating or not self.game or self.closing:
            return
        self.updating = True
        self.next_update = time.monotonic() + self.core.UPDATE_EVERY
        self.update_button.state(['disabled'])
        game, config = self.game, dict(self.config)
        if install and self.addon_release:
            self.addon_text.set(f'Installing {self.addon_release["version"]}…')

        def work():
            try:
                self.events.put(('addon', self.core.addon_pass(game, config, install=install)))
            except Exception as error:
                self.events.put(('addon_error', self.core.describe(error)))
        threading.Thread(target=work, daemon=True).start()

    def show_addon(self, status):
        installed = status.get('installed') or 'Not installed'
        release = status.get('release')
        self.addon_release = None if status.get('development') else release
        beta = ' (beta)' if addon_update.is_beta(installed) else ''
        if status.get('result'):
            restart = status['result']['restart']
            self.addon_text.set(f'{installed}{beta} — updated, ' + ('restart the game' if restart else '/reload in game'))
        elif release and status.get('development'):
            self.addon_text.set(f'{installed} — development copy ({release["version"]} is out)')
        elif release:
            self.addon_text.set(f'{installed}{beta} — {release["version"]}{" (beta)" if release["beta"] else ""} available')
        else:
            self.addon_text.set(f'{installed}{beta} — up to date')
        self.update_button.state(['!disabled'] if self.addon_release else ['disabled'])

    # --- GitHub sign-in ---------------------------------------------------------------------------

    def refresh_share_state(self):
        """Sharing needs a GitHub sign-in: the switch is usable only then."""
        usable = self.account is not None and not self.busy and not self.args.download_only
        self.share_button.state(['!disabled'] if usable else ['disabled'])
        if self.args.download_only:
            self.share_hint.set('Sharing is off for this run (--download-only).')
        elif self.account is None:
            self.share_hint.set('Sign in to GitHub first.')
        else:
            self.share_hint.set('New full scans are checked, then shared from your account.')
        if self.login_running:
            self.login_button.configure(text='Cancel')
        elif self.account and self.account[1] == 'helper':
            self.login_button.configure(text='Sign out')
        else:
            self.login_button.configure(text='Sign in with GitHub')
        self.login_button.state(['!disabled'])  # a sign-in here replaces one of the GitHub CLI
        if not self.login_running:
            self.code_box.pack_forget()
        if self.account:
            self.account_text.set(f'Signed in as {self.account[0]}{SOURCES.get(self.account[1], "")}')
        elif not self.login_running:
            self.account_text.set('Not signed in')

    def check_account(self):
        def work():
            token, source = self.core.token_source(self.config)
            if not token:
                self.events.put(('account', None))
                return
            try:
                login = github_login.whoami(token, f'ForeverFlipSync/{self.core.VERSION}')
            except Exception:
                login = 'GitHub'  # offline: the sign-in is kept, its name is read later
            self.events.put(('account', (login, source)))
        threading.Thread(target=work, daemon=True).start()

    def sign_in_or_out(self):
        if self.login_running:
            self.login_cancel = True
            return
        if self.account and self.account[1] == 'helper':
            github_login.forget(self.folder)
            self.account, self.session = None, None
            self.core.log('Signed out of GitHub. To revoke the access on GitHub too: Settings > Applications > '
                          'Authorized GitHub Apps.')
            self.check_account()  # another sign-in (the GitHub CLI) may still be there
            self.refresh_share_state()
            return
        cid = github_login.client_id(self.config)
        if not cid:
            messagebox.showinfo('Sign in with GitHub', 'Signing in from the helper is not set up in this build yet.',
                                parent=self.root)
            return
        self.login_running, self.login_cancel = True, False
        self.account_text.set('Asking GitHub for a code…')
        self.refresh_share_state()
        self.progress.start()
        agent = f'ForeverFlipSync/{self.core.VERSION}'

        def work():
            try:
                device = github_login.start(cid, agent)
                self.events.put(('login_code', device))
                token = github_login.wait_for_token(cid, device, cancelled=lambda: self.login_cancel or self.closing,
                                                    agent=agent)
                github_login.save_token(self.folder, token)
                try:
                    login = github_login.whoami(token, agent)
                except Exception:
                    login = 'GitHub'
                self.events.put(('signed_in', login))
            except Exception as error:
                self.events.put(('login_error', self.core.describe(error)))
        threading.Thread(target=work, daemon=True).start()

    def login_finished(self):
        self.login_running = False
        if not self.busy:
            self.progress.stop()
        self.refresh_share_state()

    # --- Game and sync ----------------------------------------------------------------------------

    def discover(self):
        def work():
            try:
                given = self.args.game or os.environ.get('FF_GAME') or self.config.get('game')
                self.events.put(('game', self.core.find_game(given)))
            except (GameNotFound, AmbiguousGame) as error:
                self.events.put(('setup', error))
            except Exception as error:
                self.events.put(('setup', GameNotFound(str(error))))
        threading.Thread(target=work, daemon=True).start()

    def select_game(self, value):
        game = normalize_game(value)
        if game is None:
            messagebox.showerror('Choose WoW Forever', 'Choose the Forever game folder or its parent installation folder.', parent=self.root)
            return
        try:
            self.config['game'] = str(game)
            self.core.save_json(self.folder/'config.json', self.config)
        except OSError as error:
            self.status.set(f'Could not save this folder: {error}')
            return
        self.game, self.session = game, None
        self.path.set(str(game))
        self.path_text.set(shorten(str(game)))
        self.locations.pack_forget()
        if str(game) not in self.locations['values']:
            self.locations.configure(values=(*self.locations['values'], str(game)))
        self.status.set('Ready' if self.auto.get() else 'Automatic sync paused')
        self.tone('ok' if self.auto.get() else 'idle')
        self.sync_button.state(['!disabled'])

    def choose_game(self):
        chosen = filedialog.askdirectory(title='Choose WoW Forever or its parent installation folder',
                                        initialdir=str(self.game.parent) if self.game else None, parent=self.root)
        if chosen:
            self.select_game(chosen)

    def options_changed(self):
        self.config['automatic'], self.config['upload'] = self.auto.get(), self.share.get()
        try:
            self.core.save_json(self.folder/'config.json', self.config)
        except OSError as error:
            self.status.set(f'Could not save options: {error}')
        if not self.busy:
            self.session = None
            self.status.set('Ready' if self.auto.get() else 'Automatic sync paused')
            self.tone('ok' if self.auto.get() else 'idle')

    def start_sync(self, force=False):
        if self.busy or not self.game or self.closing:
            return
        self.set_busy(True)
        share = self.share.get() and self.account is not None
        self.status.set('Sharing scans and getting prices…' if share else 'Getting community prices…')
        game = self.game

        def work():
            try:
                if self.session is None:
                    state_path = self.folder/'state.json'
                    state = self.core.load_json(state_path, {})
                    if not isinstance(state, dict):
                        state = {}
                    self.session = self.core.SyncSession(game, self.args.repo or self.config.get('repo') or self.core.DEFAULT_REPO,
                                                         state, state_path, None, share, self.config)
                if self.session.upload != share:
                    # Account discovery and the sharing switch can finish during an earlier download.
                    # Reconsider unchanged saves when the effective sharing mode changes.
                    self.session.upload = share
                    self.session.last_seen = {}
                    self.session.retry_at = 0
                self.session.refresh_credentials(self.config, force=force)
                if not self.core.saved_variable_files(game):
                    self.core.log('No saved ForeverFlip scan yet. Make a full scan in game, then /reload.')
                count = self.session.sync(force=force)
                self.events.put(('synced', count))
            except Exception as error:
                self.events.put(('error', str(error)))
        threading.Thread(target=work, daemon=True).start()

    def poll(self):
        while True:
            try:
                kind, value = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == 'log':
                self.output.configure(state='normal')
                self.output.insert('end', value+'\n')
                if int(self.output.index('end-1c').split('.')[0]) > 400:
                    self.output.delete('1.0', '50.0')
                self.output.see('end')
                self.output.configure(state='disabled')
            elif kind == 'game':
                self.set_busy(False)
                self.select_game(value)
            elif kind == 'setup':
                self.set_busy(False)
                self.status.set(str(value))
                self.tone('warn')
                self.path_text.set('Not found — press Change to choose it')
                if isinstance(value, AmbiguousGame):
                    self.path_text.set('Several installations — choose one:')
                    self.locations.configure(values=[str(p) for p in value.candidates])
                    self.locations.pack(side='left', padx=(self.s(8), 0))
            elif kind == 'addon':
                self.updating = False
                self.show_addon(value)
            elif kind == 'addon_error':
                self.updating = False
                self.addon_text.set('Could not check for updates')
                self.core.log(f'Addon update: {value}.')
                self.update_button.state(['!disabled'] if self.addon_release else ['disabled'])
            elif kind == 'account':
                self.account = value
                self.refresh_share_state()
            elif kind == 'login_code':
                code, url = value['user_code'], value['verification_uri']
                self.refresh_share_state()
                try:
                    self.root.clipboard_clear()
                    self.root.clipboard_append(code)
                except tk.TclError:
                    pass
                self.code_text.set(code)
                self.code_box.pack(anchor='w', fill='x', pady=(self.s(10), 0))
                self.account_text.set('Waiting for your approval on GitHub…')
                self.core.log(f'Sign in: enter the code {code} at {url} (copied; the page is opening) and approve.')
                webbrowser.open(url)
            elif kind == 'signed_in':
                self.account, self.session = (value, 'helper'), None
                self.core.log(f'Signed in to GitHub as {value}. Your scans are shared from now on.')
                if not self.args.download_only and not self.share.get():
                    self.share.set(True)
                    self.options_changed()
                self.login_finished()
            elif kind == 'login_error':
                self.core.log(f'Not signed in: {value}.')
                self.login_finished()
            elif kind in ('synced', 'error'):
                self.set_busy(False)
                if kind == 'synced':
                    self.last_sync.set(('Community prices updated' if value else 'No community prices yet')
                                       + ' · ' + time.strftime('%H:%M'))
                    self.status.set('Up to date')
                    self.tone('ok')
                    if self.share.get() and self.account is None:
                        self.status.set('Sign in to GitHub to share your scans')
                        self.tone('warn')
                    if not self.auto.get():
                        self.status.set(self.status.get()+' · automatic sync paused')
                else:
                    self.status.set('Could not finish — retrying in 30 seconds' if self.auto.get() else 'Could not finish — press Sync now')
                    self.tone('error')
                    self.core.log(value)
                if self.closing:
                    self.root.destroy()
                    return
        if not self.updating and not self.closing and self.game and time.monotonic() >= self.next_update:
            self.start_update()
        if not self.busy and not self.closing and self.auto.get() and self.game and time.monotonic() >= self.next_check:
            self.next_check = time.monotonic() + 5
            try:
                share = self.share.get() and self.account is not None
                if self.session is None or self.session.upload != share or self.session.due():
                    self.start_sync()
            except OSError as error:
                self.status.set(str(error))
        if self.closing and not self.busy:
            self.root.destroy()
            return
        self.poll_job = self.root.after(250, self.poll)

    def close(self):
        if self.busy:
            self.closing = True
            self.auto.set(False)
            self.status.set('Finishing the current operation before closing…')
        else:
            if getattr(self, 'poll_job', None):
                self.root.after_cancel(self.poll_job)
            self.progress.stop()
            self.root.destroy()


def launch(args, config, folder, core):
    if os.name == 'nt':
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except (AttributeError, OSError):
            pass
    root = tk.Tk()
    SyncWindow(root, args, config, pathlib.Path(folder), core)
    root.mainloop()
    core.LOG_SINK = None
    return 0
