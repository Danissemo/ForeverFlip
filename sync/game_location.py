"""Bounded discovery of the game clients ForeverFlip runs in: WoW Forever and WoW Retail.
Classic, PTR and beta folders are never taken for them."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys

GAME_PATHS = [r'C:\World of Warcraft\_forever_', r'C:\Program Files (x86)\World of Warcraft\_forever_',
              r'C:\Program Files\World of Warcraft\_forever_', r'D:\World of Warcraft\_forever_',
              r'C:\Program Files (x86)\World of Warcraft\_retail_', r'C:\World of Warcraft\_retail_']
CLIENTS = {'_forever_': 'wowf', '_retail_': 'wow'}  # client folder -> its Battle.net product
OTHER_CLIENTS = {'_classic_', '_classic_era_', '_ptr_', '_xptr_', '_beta_'}


class GameNotFound(ValueError):
    pass


class AmbiguousGame(ValueError):
    def __init__(self, candidates):
        self.candidates = candidates
        super().__init__('Several WoW installations were found. Choose the one you play.')


def _products(folder: pathlib.Path) -> set:
    try:
        lines = (folder / '.build.info').read_text(encoding='utf-8-sig').splitlines()
        fields = [field.split('!')[0] for field in lines[0].split('|')]
        product = fields.index('Product')
        active = fields.index('Active') if 'Active' in fields else None
        products = {parts[product] for parts in (line.split('|') for line in lines[1:])
                    if len(parts) > product and (active is None or len(parts) > active and parts[active] == '1')}
        return products
    except (OSError, ValueError, IndexError):
        return set()


def _is_game(folder: pathlib.Path) -> bool:
    return (folder.name.lower() not in OTHER_CLIENTS
            and (folder / 'Interface' / 'AddOns').is_dir()
            and (folder / 'Wow.exe').is_file()
            and (folder.name.lower() in CLIENTS
                 or any(_products(where) in ({'wowf'}, {'wow'}) for where in (folder, folder.parent))))


def normalize_game(given) -> pathlib.Path | None:
    if not given:
        return None
    path = pathlib.Path(os.path.expandvars(str(given).strip().strip('"'))).expanduser()
    try:
        if not path.exists():
            return None
        path = path.resolve()
        if path.is_file():
            path = path.parent
        if any(parent.name.lower() in OTHER_CLIENTS for parent in (path, *path.parents)):
            return None
        for parent in (path, *list(path.parents)[:4]):
            for candidate in (parent / '_forever_', parent / '_retail_', parent):
                if _is_game(candidate):
                    return candidate.resolve()
    except (OSError, RuntimeError):
        return None
    return None


def windows_locations() -> list[str]:
    if os.name != 'nt':
        return []
    import winreg
    locations = []
    for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        for key_name in (r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                         r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'):
            try:
                with winreg.OpenKey(hive, key_name) as parent:
                    for i in range(winreg.QueryInfoKey(parent)[0]):
                        try:
                            with winreg.OpenKey(parent, winreg.EnumKey(parent, i)) as key:
                                name = str(winreg.QueryValueEx(key, 'DisplayName')[0]).lower()
                                if 'warcraft' in name or 'forever' in name:
                                    location = str(winreg.QueryValueEx(key, 'InstallLocation')[0])
                                    if location:
                                        locations.append(location)
                        except OSError:
                            continue
            except OSError:
                continue
    return locations


def running_locations() -> list[str]:
    if os.name != 'nt':
        return []
    command = ("[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); "
               "Get-Process -Name Wow,WowClassic -ErrorAction SilentlyContinue | "
               "Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue")
    try:
        result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=8,
                                creationflags=subprocess.CREATE_NO_WINDOW)
        return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except (OSError, subprocess.SubprocessError):
        return []


def common_locations() -> list[pathlib.Path]:
    roots = [pathlib.Path.cwd(), pathlib.Path(sys.executable).parent]
    roots.extend(pathlib.Path(p) for p in GAME_PATHS)
    if os.environ.get('FF_GAME'):
        roots.insert(0, pathlib.Path(os.environ['FF_GAME']))
    if os.name == 'nt':
        import ctypes
        mask = ctypes.windll.kernel32.GetLogicalDrives()
        for i in range(26):
            if mask & (1 << i):
                drive = f'{chr(65+i)}:\\'
                if ctypes.windll.kernel32.GetDriveTypeW(drive) not in (2, 3):
                    continue
                for relative in ('World of Warcraft', 'WOW/World of Warcraft', 'Games/World of Warcraft', 'Games/WoW',
                                 'WoW', 'Battle.net/World of Warcraft', 'Program Files/World of Warcraft',
                                 'Program Files (x86)/World of Warcraft'):
                    roots.append(pathlib.Path(drive) / relative)
    return roots


def discover_games(paths=None) -> list[pathlib.Path]:
    candidates = paths if paths is not None else running_locations() + windows_locations() + common_locations()
    found = {}
    for candidate in candidates:
        for game in [normalize_game(candidate)] + [normalize_game(pathlib.Path(str(candidate)) / name)
                                                   for name in CLIENTS]:
            if game is not None:
                found[os.path.normcase(str(game))] = game
    return sorted(found.values(), key=lambda p: str(p).casefold())


def locate_game(given: str | None = None) -> pathlib.Path:
    if given:
        game = normalize_game(given)
        if game is None:
            raise GameNotFound('The selected folder is not a WoW Forever or WoW Retail client. Choose its game folder or Wow.exe.')
        return game
    games = discover_games()
    if len(games) == 1:
        return games[0]
    if len(games) > 1:
        raise AmbiguousGame(games)
    raise GameNotFound('WoW was not found. Choose the game folder; a parent installation folder also works.')
