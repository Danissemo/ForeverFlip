# ForeverFlip 5

Auction-window addon for WoW Forever 1.60.1, Interface 16001. Pre-release until
live-client checks validate the native protected-action paths.

Money/source formats: [ForeverFlip/DATA_FORMATS.md](ForeverFlip/DATA_FORMATS.md).

Run tests with Python 3.12 and `lupa==2.8` (module `lupa.lua51`):

```powershell
python -m unittest discover -s tests -v
python tools/build.py --output dist
```

The build verifies all tests, compiles every TOC module with Lua 5.1, validates
the archive and emits SHA-256. It never changes live addons or SavedVariables.
No network service or subscription is required. There is no bundled TSM Premium
code or data; the addon implements its own models and limited formula language.
