"""Small desktop front end. Tk owns the UI; one worker owns each sync operation."""

from __future__ import annotations

import os
import pathlib
import queue
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from game_location import AmbiguousGame, GameNotFound, normalize_game


class SyncWindow:
    def __init__(self, root, args, config, folder, core):
        self.root, self.args, self.config, self.folder, self.core = root, args, config, folder, core
        self.events = queue.Queue()
        self.game = self.session = None
        self.busy = self.closing = False
        self.next_check = 0.0
        self.auto = tk.BooleanVar(value=not args.paused and config.get('automatic', True))
        self.share = tk.BooleanVar(value=not args.download_only and (args.upload or bool(config.get('upload', False))))
        self.status = tk.StringVar(value='Finding your Forever installation...')
        self.last_sync = tk.StringVar(value='Not synced yet')
        self.path = tk.StringVar()
        root.title('ForeverFlip Sync')
        root.geometry('720x500')
        root.minsize(620, 420)
        root.protocol('WM_DELETE_WINDOW', self.close)
        main = ttk.Frame(root, padding=20)
        main.pack(fill='both', expand=True)
        main.columnconfigure(0, weight=1)
        main.rowconfigure(8, weight=1)
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
        if args.download_only:
            self.share_button.state(['disabled'])
        controls = ttk.Frame(main)
        controls.grid(row=5, column=0, columnspan=2, sticky='ew', pady=(16, 8))
        controls.columnconfigure(0, weight=1)
        ttk.Label(controls, textvariable=self.status, font=('Segoe UI', 10, 'bold'), wraplength=490).grid(row=0, column=0, sticky='w')
        ttk.Label(controls, textvariable=self.last_sync).grid(row=1, column=0, sticky='w', pady=(4, 0))
        self.sync_button = ttk.Button(controls, text='Sync now', command=lambda: self.start_sync(force=True))
        self.sync_button.grid(row=0, column=1, rowspan=2, sticky='e', padx=(12, 0))
        self.sync_button.state(['disabled'])
        self.progress = ttk.Progressbar(main, mode='indeterminate')
        self.progress.grid(row=6, column=0, columnspan=2, sticky='ew', pady=(0, 10))
        ttk.Label(main, text='In game: /reload saves new scans and applies updated prices.\n'
                  'Enable full-scan saving in Settings > Sharing to contribute. Restart the game after the first community-addon install.',
                  wraplength=660).grid(row=7, column=0, columnspan=2, sticky='w', pady=(0, 12))
        log_frame = ttk.Frame(main)
        log_frame.grid(row=8, column=0, columnspan=2, sticky='nsew')
        self.output = tk.Text(log_frame, height=9, wrap='word', state='disabled', font=('Consolas', 9), relief='flat')
        scroll = ttk.Scrollbar(log_frame, command=self.output.yview)
        self.output.configure(yscrollcommand=scroll.set)
        scroll.pack(side='right', fill='y')
        self.output.pack(side='left', fill='both', expand=True)
        core.LOG_SINK = lambda line: self.events.put(('log', line))
        self.set_busy(True)
        root.after(50, self.discover)
        root.after(100, self.poll)

    def set_busy(self, value):
        self.busy = value
        for button in (self.choose_button, self.share_button):
            button.state(['disabled'] if value else ['!disabled'])
        if self.args.download_only:
            self.share_button.state(['disabled'])
        self.locations.configure(state='disabled' if value else 'readonly')
        self.sync_button.state(['disabled'] if value or not self.game else ['!disabled'])
        if value:
            self.progress.start(12)
        else:
            self.progress.stop()
            self.progress['value'] = 0

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
        self.status.set('Syncing scans and community prices...' if self.share.get() else 'Getting community prices...')
        game, share = self.game, self.share.get()

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
            elif kind in ('synced', 'error'):
                self.set_busy(False)
                if kind == 'synced':
                    self.last_sync.set('Last sync: '+time.strftime('%H:%M:%S'))
                    self.status.set('Up to date' if value is None or value > 0 else 'No community prices yet')
                    if self.share.get() and self.session and not self.session.token:
                        if self.session.state.get('anonymous'):
                            self.status.set(self.status.get()+' — scans shared anonymously')
                        else:
                            self.status.set('Prices checked — anonymous sharing is not available yet; sign in to GitHub to share')
                    if not self.auto.get():
                        self.status.set(self.status.get()+' — automatic sync paused')
                else:
                    self.status.set('Could not finish — automatic retry in 30 seconds' if self.auto.get() else 'Could not finish — press Sync now to retry')
                    self.core.log(value)
                if self.closing:
                    self.root.destroy()
                    return
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
