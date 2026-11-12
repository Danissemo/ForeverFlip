"""Small desktop front end. Tk owns the UI; one worker owns each sync operation.

The look is drawn by hand (flat buttons, pill switches, one white card of settings rows), because
the stock Windows widgets of Tk look dated. The widgets keep the ttk-style state()/instate() calls.
"""

from __future__ import annotations

import os
import pathlib
import queue
import threading
import time
import tkinter as tk
import webbrowser
from tkinter import filedialog, font as tkfont, messagebox, ttk

import addon_update
import github_login
from game_location import AmbiguousGame, GameNotFound, normalize_game

SOURCES = {'helper': '', 'gh': ' (GitHub CLI)', 'environment': ' (FF_GITHUB_TOKEN)', 'config': ' (config.json)'}

# Palette: a light window, one white card, one accent.
BG = '#F4F5F7'
CARD = '#FFFFFF'
LINE = '#E6E8EB'
TEXT = '#1F2328'
MUTED = '#6B7280'
FAINT = '#A3A9B1'
ACCENT = '#2563EB'
ACCENT_HOVER = '#1D4ED8'
SOFT = '#EEF2FF'
TONES = {'ok': '#16A34A', 'busy': ACCENT, 'warn': '#D97706', 'error': '#DC2626', 'idle': FAINT}


def fonts(root):
    family = 'Segoe UI' if 'Segoe UI' in tkfont.families(root) else 'TkDefaultFont'
    return {
        'title': (family, 15, 'bold'),
        'body': (family, 10),
        'strong': (family, 10, 'bold'),
        'small': (family, 9),
        'label': (family, 9, 'bold'),
        'code': ('Consolas', 18, 'bold'),
        'log': ('Consolas', 9),
    }


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


class FlatButton(Widget, tk.Label):
    """A flat button: "primary" (filled accent), "secondary" (outlined) or "link" (accent text)."""

    def __init__(self, master, text, command, kind='secondary', font=None, bg=CARD):
        tk.Label.__init__(self, master, text=text, font=font, cursor='hand2', padx=14, pady=5, bd=0,
                          highlightthickness=1)
        self.command, self.kind, self.base = command, kind, bg
        self.hover = False
        self.bind('<Enter>', lambda _: self.set_hover(True))
        self.bind('<Leave>', lambda _: self.set_hover(False))
        self.bind('<ButtonRelease-1>', self.click)
        self.redraw()

    def set_hover(self, value):
        self.hover = value
        self.redraw()

    def click(self, _event=None):
        if not self.disabled and self.command:
            self.command()

    def redraw(self):
        if self.kind == 'primary':
            fill = '#C7D2FE' if self.disabled else ACCENT_HOVER if self.hover else ACCENT
            self.configure(bg=fill, fg='#FFFFFF', highlightbackground=fill, highlightcolor=fill)
        elif self.kind == 'link':
            fg = FAINT if self.disabled else ACCENT_HOVER if self.hover else ACCENT
            self.configure(bg=self.base, fg=fg, padx=0, highlightbackground=self.base, highlightcolor=self.base)
        else:
            fill = SOFT if self.hover and not self.disabled else self.base
            border = LINE if self.disabled else ACCENT if self.hover else '#D0D5DB'
            self.configure(bg=fill, fg=FAINT if self.disabled else TEXT, highlightbackground=border,
                           highlightcolor=border)
        self.configure(cursor='arrow' if self.disabled else 'hand2')


class Switch(Widget, tk.Frame):
    """A pill switch with its label, bound to a BooleanVar."""

    W, H = 34, 18

    def __init__(self, master, text, variable, command=None, font=None, bg=CARD):
        tk.Frame.__init__(self, master, bg=bg)
        self.variable, self.command = variable, command
        self.canvas = tk.Canvas(self, width=self.W, height=self.H, bg=bg, highlightthickness=0, bd=0, cursor='hand2')
        self.canvas.pack(side='left')
        self.label = tk.Label(self, text=text, bg=bg, fg=TEXT, font=font, cursor='hand2', padx=6)
        self.label.pack(side='left')
        for widget in (self.canvas, self.label):
            widget.bind('<ButtonRelease-1>', self.toggle)
        variable.trace_add('write', lambda *_: self.redraw())
        self.redraw()

    def toggle(self, _event=None):
        if self.disabled:
            return
        self.variable.set(not self.variable.get())
        if self.command:
            self.command()

    def redraw(self):
        on = bool(self.variable.get())
        c, w, h = self.canvas, self.W, self.H
        c.delete('all')
        track = (('#BFD0FB' if on else '#E5E7EB') if self.disabled else (ACCENT if on else '#CBD0D6'))
        r = h / 2
        c.create_oval(0, 0, h, h, fill=track, outline=track)
        c.create_oval(w - h, 0, w, h, fill=track, outline=track)
        c.create_rectangle(r, 0, w - r, h, fill=track, outline=track)
        x = w - h + 2 if on else 2
        c.create_oval(x, 2, x + h - 4, h - 2, fill='#FFFFFF', outline='#FFFFFF')
        self.label.configure(fg=FAINT if self.disabled else TEXT)
        cursor = 'arrow' if self.disabled else 'hand2'
        c.configure(cursor=cursor)
        self.label.configure(cursor=cursor)


class ActivityBar(tk.Canvas):
    """A thin moving bar while something runs; flat and empty otherwise."""

    def __init__(self, master):
        super().__init__(master, height=3, bg=BG, highlightthickness=0, bd=0)
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


def shorten(path: str, limit: int = 52) -> str:
    return path if len(path) <= limit else path[:18] + '…' + path[-(limit - 19):]


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
        f = self.f = fonts(root)

        root.title('ForeverFlip Sync')
        root.configure(bg=BG)
        root.minsize(620, 0)
        root.protocol('WM_DELETE_WINDOW', self.close)

        # Header: name, one-line purpose, and the overall status on the right.
        head = tk.Frame(root, bg=BG)
        head.pack(fill='x', padx=28, pady=(22, 12))
        left = tk.Frame(head, bg=BG)
        left.pack(side='left')
        tk.Label(left, text='ForeverFlip Sync', font=f['title'], bg=BG, fg=TEXT).pack(anchor='w')
        tk.Label(left, text='Community prices and addon updates for WoW Forever', font=f['small'], bg=BG,
                 fg=MUTED).pack(anchor='w')
        pill = tk.Frame(head, bg=BG)
        pill.pack(side='right', anchor='n', pady=(4, 0))
        self.dot = tk.Canvas(pill, width=10, height=10, bg=BG, highlightthickness=0)
        self.dot.pack(side='left', padx=(0, 7))
        tk.Label(pill, textvariable=self.status, font=f['small'], bg=BG, fg=MUTED, wraplength=280,
                 justify='right').pack(side='left')
        self.tone('idle')
        self.progress = ActivityBar(root)
        self.progress.pack(fill='x', padx=28)

        # The card of settings rows.
        card = tk.Frame(root, bg=CARD, highlightthickness=1, highlightbackground=LINE)
        card.pack(fill='x', padx=28, pady=(10, 0))
        card.columnconfigure(1, weight=1)
        self.card, self.row_count = card, 0

        game = self.row('Game')
        tk.Label(game, textvariable=self.path_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(side='left')
        self.locations = ttk.Combobox(game, textvariable=self.path, state='readonly', width=46)
        self.locations.bind('<<ComboboxSelected>>', lambda _: self.select_game(self.path.get()))
        self.choose_button = FlatButton(self.actions, 'Change', self.choose_game, 'link', f['body'])
        self.choose_button.pack(side='right')

        github = self.row('GitHub')
        tk.Label(github, textvariable=self.account_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        self.code_box = tk.Frame(github, bg=SOFT, padx=12, pady=8)
        tk.Label(self.code_box, textvariable=self.code_text, font=f['code'], bg=SOFT, fg=ACCENT).pack(anchor='w')
        tk.Label(self.code_box, text='Copied. Paste it on the page that opened and approve ForeverFlip Sync.',
                 font=f['small'], bg=SOFT, fg=MUTED, justify='left', wraplength=300).pack(anchor='w')
        self.login_button = FlatButton(self.actions, 'Sign in with GitHub', self.sign_in_or_out, 'secondary', f['body'])
        self.login_button.pack(side='right')

        sharing = self.row('Sharing')
        self.share_button = Switch(sharing, 'Share my full scans', self.share, self.options_changed, f['body'])
        self.share_button.pack(anchor='w')
        tk.Label(sharing, textvariable=self.share_hint, font=f['small'], bg=CARD, fg=MUTED, anchor='w',
                 justify='left', wraplength=330).pack(anchor='w', pady=(3, 0))

        addon = self.row('Addon')
        tk.Label(addon, textvariable=self.addon_text, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        toggles = tk.Frame(addon, bg=CARD)
        toggles.pack(anchor='w', pady=(6, 0))
        Switch(toggles, 'Install updates', self.update_auto, self.addon_options_changed, f['small']).pack(side='left')
        Switch(toggles, 'Beta tester', self.beta, self.addon_options_changed, f['small']).pack(side='left', padx=(14, 0))
        self.update_button = FlatButton(self.actions, 'Update', lambda: self.start_update(install=True), 'secondary',
                                        f['body'])
        self.update_button.pack(side='right')
        self.update_button.state(['disabled'])

        prices = self.row('Prices', last=True)
        tk.Label(prices, textvariable=self.last_sync, font=f['body'], bg=CARD, fg=TEXT, anchor='w').pack(anchor='w')
        self.auto_button = Switch(prices, 'Sync automatically', self.auto, self.options_changed, f['small'])
        self.auto_button.pack(anchor='w', pady=(6, 0))
        self.sync_button = FlatButton(self.actions, 'Sync now', lambda: self.start_sync(force=True), 'primary',
                                      f['strong'])
        self.sync_button.pack(side='right')
        self.sync_button.state(['disabled'])

        # Footer: the in-game step, and the activity log behind a link.
        foot = tk.Frame(root, bg=BG)
        foot.pack(fill='x', padx=28, pady=(12, 0))
        tk.Frame(root, bg=BG, height=20).pack(side='bottom')  # bottom margin
        tk.Label(foot, text='After a sync, type /reload in game to read the new prices.', font=f['small'], bg=BG,
                 fg=MUTED).pack(side='left')
        self.log_button = FlatButton(foot, 'Show activity', self.toggle_log, 'link', f['small'], bg=BG)
        self.log_button.pack(side='right')
        self.log_frame = tk.Frame(root, bg=CARD, highlightthickness=1, highlightbackground=LINE)
        self.output = tk.Text(self.log_frame, width=1, height=8, wrap='word', state='disabled', font=f['log'], relief='flat',
                              bg=CARD, fg=MUTED, bd=0, padx=12, pady=10, highlightthickness=0)
        scroll = ttk.Scrollbar(self.log_frame, command=self.output.yview)
        self.output.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.output.pack(side='left', fill='both', expand=True)

        self.refresh_share_state()
        core.LOG_SINK = lambda line: self.events.put(('log', line))
        self.set_busy(True)
        root.after(50, self.discover)
        root.after(60, self.check_account)
        root.after(100, self.poll)

    def row(self, title, last=False):
        """A settings row of the card: its title, a content frame (returned) and self.actions."""
        r = self.row_count
        self.row_count += 1
        tk.Label(self.card, text=title.upper(), font=self.f['label'], bg=CARD, fg=FAINT, anchor='nw', width=9).grid(
            row=2 * r, column=0, sticky='nw', padx=(20, 8), pady=(16, 14))
        content = tk.Frame(self.card, bg=CARD)
        content.grid(row=2 * r, column=1, sticky='ew', pady=(14, 14))
        self.actions = tk.Frame(self.card, bg=CARD)
        self.actions.grid(row=2 * r, column=2, sticky='ne', padx=(8, 20), pady=(12, 12))
        if not last:
            tk.Frame(self.card, bg=LINE, height=1).grid(row=2 * r + 1, column=0, columnspan=3, sticky='ew', padx=20)
        return content

    def tone(self, name):
        self.dot.delete('all')
        color = TONES.get(name, FAINT)
        self.dot.create_oval(1, 1, 9, 9, fill=color, outline=color)

    def toggle_log(self):
        self.log_open = not self.log_open
        if self.log_open:
            self.log_frame.pack(fill='both', expand=True, padx=28, pady=(8, 0))
            self.log_button.configure(text='Hide activity')
        else:
            self.log_frame.pack_forget()
            self.log_button.configure(text='Show activity')
        self.root.geometry('')  # the window takes the height of what it shows

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
                    self.locations.pack(side='left', padx=(8, 0))
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
                self.code_box.pack(anchor='w', fill='x', pady=(8, 0))
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
                if self.session is None or self.session.due():
                    self.start_sync()
            except OSError as error:
                self.status.set(str(error))
        if self.closing and not self.busy:
            self.root.destroy()
            return
        self.root.after(250, self.poll)

    def close(self):
        if self.busy:
            self.closing = True
            self.auto.set(False)
            self.status.set('Finishing the current operation before closing…')
        else:
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
