"""Small desktop front end. Tk owns the UI; one worker owns each sync operation."""

from __future__ import annotations

import os
import pathlib
import queue
import threading
import time
import tkinter as tk
import webbrowser
from tkinter import filedialog, messagebox, ttk

import addon_update
import github_login
from game_location import AmbiguousGame, GameNotFound, normalize_game

SOURCES = {'helper': '', 'gh': ' (GitHub CLI)', 'environment': ' (FF_GITHUB_TOKEN)', 'config': ' (config.json)'}


class SyncWindow:
    def __init__(self, root, args, config, folder, core):
        self.root, self.args, self.config, self.folder, self.core = root, args, config, folder, core
        self.events = queue.Queue()
        self.game = self.session = None
        self.busy = self.closing = False
        self.next_check = 0.0
        self.account = None  # (login, source) once signed in to GitHub
        self.login_running = self.login_cancel = False
        self.account_text = tk.StringVar(value='Checking the GitHub sign-in...')
        self.updating = False
        self.next_update = 0.0
        self.addon_release = None  # a newer release found and not installed
        self.addon_text = tk.StringVar(value='Addon: checking for updates...')
        self.update_auto = tk.BooleanVar(value=config.get('update_addon', True))
        self.beta = tk.BooleanVar(value=config.get('beta', False))
        self.auto = tk.BooleanVar(value=not args.paused and config.get('automatic', True))
        self.share = tk.BooleanVar(value=not args.download_only and (args.upload or bool(config.get('upload', False))))
        self.status = tk.StringVar(value='Finding your Forever installation...')
        self.last_sync = tk.StringVar(value='Not synced yet')
        self.path = tk.StringVar()
        root.title('ForeverFlip Sync')
        root.geometry('760x560')
        root.minsize(660, 480)
        root.protocol('WM_DELETE_WINDOW', self.close)
        main = ttk.Frame(root, padding=20)
        main.pack(fill='both', expand=True)
        main.columnconfigure(0, weight=1)
        main.rowconfigure(9, weight=1)
        ttk.Label(main, text='ForeverFlip Sync', font=('Segoe UI', 19, 'bold')).grid(row=0, column=0, columnspan=2, sticky='w')
        ttk.Label(main, text='Auction scans and community prices, without moving files by hand.').grid(
            row=1, column=0, columnspan=2, sticky='w', pady=(2, 18))
        ttk.Label(main, text='Game installation').grid(row=2, column=0, sticky='w')
        self.choose_button = ttk.Button(main, text='Choose game...', command=self.choose_game)
        self.choose_button.grid(row=2, column=1, rowspan=2, sticky='e', padx=(12, 0))
        self.locations = ttk.Combobox(main, textvariable=self.path, state='readonly')
        self.locations.grid(row=3, column=0, sticky='ew', pady=(4, 12))
        self.locations.bind('<<ComboboxSelected>>', lambda _: self.select_game(self.path.get()))
        modes = ttk.Frame(main)
        modes.grid(row=4, column=0, columnspan=2, sticky='ew')
        self.auto_button = ttk.Checkbutton(modes, text='Sync automatically', variable=self.auto, command=self.options_changed)
        self.auto_button.pack(side='left')
        self.share_button = ttk.Checkbutton(modes, text='Share my full scans', variable=self.share, command=self.options_changed)
        self.share_button.pack(side='left', padx=(20, 0))
        self.login_button = ttk.Button(modes, text='Sign in with GitHub', command=self.sign_in_or_out)
        self.login_button.pack(side='right')
        ttk.Label(modes, textvariable=self.account_text).pack(side='right', padx=(0, 10))
        self.refresh_share_state()
        addon = ttk.Frame(main)
        addon.grid(row=5, column=0, columnspan=2, sticky='ew', pady=(10, 0))
        ttk.Label(addon, textvariable=self.addon_text).pack(side='left')
        self.update_button = ttk.Button(addon, text='Update now', command=lambda: self.start_update(install=True))
        self.update_button.pack(side='right')
        self.update_button.state(['disabled'])
        ttk.Checkbutton(addon, text='Beta tester', variable=self.beta, command=self.addon_options_changed).pack(
            side='right', padx=(0, 12))
        ttk.Checkbutton(addon, text='Update automatically', variable=self.update_auto,
                        command=self.addon_options_changed).pack(side='right', padx=(0, 12))
        controls = ttk.Frame(main)
        controls.grid(row=6, column=0, columnspan=2, sticky='ew', pady=(16, 8))
        controls.columnconfigure(0, weight=1)
        ttk.Label(controls, textvariable=self.status, font=('Segoe UI', 10, 'bold'), wraplength=490).grid(row=0, column=0, sticky='w')
        ttk.Label(controls, textvariable=self.last_sync).grid(row=1, column=0, sticky='w', pady=(4, 0))
        self.sync_button = ttk.Button(controls, text='Sync now', command=lambda: self.start_sync(force=True))
        self.sync_button.grid(row=0, column=1, rowspan=2, sticky='e', padx=(12, 0))
        self.sync_button.state(['disabled'])
        self.progress = ttk.Progressbar(main, mode='indeterminate')
        self.progress.grid(row=7, column=0, columnspan=2, sticky='ew', pady=(0, 10))
        ttk.Label(main, text='In game: /reload saves new scans and applies updated prices.\n'
                  'Enable full-scan saving in Settings > Sharing to contribute. Restart the game after the first community-addon install.',
                  wraplength=700).grid(row=8, column=0, columnspan=2, sticky='w', pady=(0, 12))
        log_frame = ttk.Frame(main)
        log_frame.grid(row=9, column=0, columnspan=2, sticky='nsew')
        self.output = tk.Text(log_frame, height=9, wrap='word', state='disabled', font=('Consolas', 9), relief='flat')
        scroll = ttk.Scrollbar(log_frame, command=self.output.yview)
        self.output.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.output.pack(side='left', fill='both', expand=True)
        core.LOG_SINK = lambda line: self.events.put(('log', line))
        self.set_busy(True)
        root.after(50, self.discover)
        root.after(60, self.check_account)
        root.after(100, self.poll)

    def set_busy(self, value):
        self.busy = value
        self.choose_button.state(['disabled'] if value else ['!disabled'])
        self.refresh_share_state()
        self.locations.configure(state='disabled' if value else 'readonly')
        self.sync_button.state(['disabled'] if value or not self.game else ['!disabled'])
        if value:
            self.progress.start(12)
        else:
            self.progress.stop()
            self.progress['value'] = 0

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
            self.addon_text.set(f'Addon: installing {self.addon_release["version"]}...')

        def work():
            try:
                self.events.put(('addon', self.core.addon_pass(game, config, install=install)))
            except Exception as error:
                self.events.put(('addon_error', self.core.describe(error)))
        threading.Thread(target=work, daemon=True).start()

    def show_addon(self, status):
        installed = status.get('installed') or 'not installed'
        release = status.get('release')
        self.addon_release = None if status.get('development') else release
        beta = ' (beta)' if addon_update.is_beta(installed) else ''
        if status.get('result'):
            restart = status['result']['restart']
            self.addon_text.set(f'Addon {installed}{beta}: updated — ' + ('restart the game' if restart else '/reload in game'))
        elif release and status.get('development'):
            self.addon_text.set(f'Addon {installed}: development copy ({release["version"]} is out)')
        elif release:
            self.addon_text.set(f'Addon {installed}{beta}: {release["version"]}{" (beta)" if release["beta"] else ""} available')
        else:
            self.addon_text.set(f'Addon {installed}{beta}: up to date')
        self.update_button.state(['!disabled'] if self.addon_release else ['disabled'])

    # --- GitHub sign-in ---------------------------------------------------------------------------

    def refresh_share_state(self):
        """Sharing needs a GitHub sign-in: the checkbox is usable only then."""
        usable = self.account is not None and not self.busy and not self.args.download_only
        self.share_button.state(['!disabled'] if usable else ['disabled'])
        if self.login_running:
            self.login_button.configure(text='Cancel sign-in')
        elif self.account and self.account[1] == 'helper':
            self.login_button.configure(text='Sign out')
        else:
            self.login_button.configure(text='Sign in with GitHub')
        self.login_button.state(['disabled'] if self.account and self.account[1] != 'helper' else ['!disabled'])
        if self.account:
            self.account_text.set(f'Signed in as {self.account[0]}{SOURCES.get(self.account[1], "")}')
        elif not self.login_running:
            self.account_text.set('Not signed in: sign in to share your scans')

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
        self.account_text.set('Asking GitHub for a code...')
        self.refresh_share_state()
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
        if str(game) not in self.locations['values']:
            self.locations.configure(values=(*self.locations['values'], str(game)))
        self.status.set('Ready' if self.auto.get() else 'Automatic sync paused')
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

    def start_sync(self, force=False):
        if self.busy or not self.game or self.closing:
            return
        self.set_busy(True)
        share = self.share.get() and self.account is not None
        self.status.set('Syncing scans and community prices...' if share else 'Getting community prices...')
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
                if isinstance(value, AmbiguousGame):
                    self.locations.configure(values=[str(p) for p in value.candidates])
            elif kind == 'addon':
                self.updating = False
                self.show_addon(value)
            elif kind == 'addon_error':
                self.updating = False
                self.addon_text.set('Addon: could not check for updates')
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
                self.account_text.set(f'Enter the code {code} at {url.replace("https://", "")}')
                self.core.log(f'Sign in: enter the code {code} at {url} (copied; the page is opening) and approve.')
                webbrowser.open(url)
            elif kind == 'signed_in':
                self.login_running = False
                self.account, self.session = (value, 'helper'), None
                self.core.log(f'Signed in to GitHub as {value}. Your scans are shared from now on.')
                if not self.args.download_only and not self.share.get():
                    self.share.set(True)
                    self.options_changed()
                self.refresh_share_state()
            elif kind == 'login_error':
                self.login_running = False
                self.core.log(f'Not signed in: {value}.')
                self.refresh_share_state()
            elif kind in ('synced', 'error'):
                self.set_busy(False)
                if kind == 'synced':
                    self.last_sync.set('Last sync: '+time.strftime('%H:%M:%S'))
                    self.status.set('Up to date' if value is None or value > 0 else 'No community prices yet')
                    if self.share.get() and self.account is None:
                        self.status.set('Prices checked — sign in to GitHub to share your scans')
                    if not self.auto.get():
                        self.status.set(self.status.get()+' — automatic sync paused')
                else:
                    self.status.set('Could not finish — automatic retry in 30 seconds' if self.auto.get() else 'Could not finish — press Sync now to retry')
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
            self.status.set('Finishing the current operation before closing...')
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
