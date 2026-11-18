"""Several game installations, each its own profile, so their markets and versions never mix.

config.json keeps the list in "installs": [{"id", "game"}], and "active" names the one the window
shows. A profile's client facts (folder flavor such as _forever_, the client version from
.build.info) are read from its folder, never stored, so a game update is seen at once. Each profile
has its own sync state (what was shared, the community exchange) and its own addon backups; the
SavedVariables and the ForeverFlip_Shared addon live in the game folder itself.

Older configs had one "game": migrate() turns it into a one-element list whose profile keeps the
old state.json, so nothing already shared is sent again. "game" is still written for the active
install, so an older helper started on the same config finds a game.
"""

from __future__ import annotations

import ntpath  # game folders are Windows paths, also when the tests run on Linux
import pathlib
import re

FIRST = "main"  # the id of the first profile: it keeps the files of the single-install helper


def same_path(a, b) -> bool:
    return ntpath.normcase(ntpath.normpath(str(a))) == ntpath.normcase(ntpath.normpath(str(b)))


def migrate(config: dict) -> bool:
    """Brings `config` to the profile list; True when it changed (save it)."""
    before = (repr(config.get("installs") or []), config.get("active"), config.get("game"))
    installs = []
    for item in config.get("installs") or []:
        if isinstance(item, dict) and item.get("game") and item.get("id") \
                and not any(i["id"] == item["id"] or same_path(i["game"], item["game"]) for i in installs):
            installs.append({"id": str(item["id"]), "game": str(item["game"])})
    if not installs and config.get("game"):
        installs.append({"id": FIRST, "game": str(config["game"])})
    config["installs"] = installs
    ids = [i["id"] for i in installs]
    if config.get("active") not in ids:
        config["active"] = ids[0] if ids else None
    active = active_install(config)
    if active:
        config["game"] = active["game"]
    return before != (repr(config.get("installs")), config.get("active"), config.get("game"))


def active_install(config: dict) -> dict | None:
    return next((i for i in config.get("installs") or [] if i["id"] == config.get("active")), None)


def find_install(config: dict, game) -> dict | None:
    return next((i for i in config.get("installs") or [] if same_path(i["game"], game)), None)


def new_id(config: dict, game) -> str:
    used = {i["id"] for i in config.get("installs") or []}
    if not used:
        return FIRST
    path = pathlib.Path(str(game))
    base = re.sub(r"[^a-z0-9]+", "-", f"{path.parent.name}-{path.name}".lower()).strip("-") or "game"
    ident, n = base, 2
    while ident in used:
        ident, n = f"{base}-{n}", n + 1
    return ident


def add_install(config: dict, game, activate: bool = True) -> dict:
    """The profile of `game` (added when new); made active when `activate`."""
    migrate(config)
    install = find_install(config, game)
    if install is None:
        install = {"id": new_id(config, game), "game": str(game)}
        config["installs"].append(install)
    if activate:
        set_active(config, install["id"])
    return install


def remove_install(config: dict, ident: str) -> bool:
    """Forgets a profile (its game folder and files stay). The last one cannot be removed."""
    installs = config.get("installs") or []
    if len(installs) <= 1 or not any(i["id"] == ident for i in installs):
        return False
    config["installs"] = [i for i in installs if i["id"] != ident]
    if config.get("active") == ident:
        config["active"] = config["installs"][0]["id"]
    migrate(config)
    return True


def set_active(config: dict, ident: str) -> dict:
    install = next(i for i in config.get("installs") or [] if i["id"] == ident)
    config["active"] = ident
    config["game"] = install["game"]
    return install


def profile_folder(folder: pathlib.Path, install: dict | None) -> pathlib.Path:
    """Where a profile keeps its files: the helper's folder for the first one (as before)."""
    folder = pathlib.Path(folder)
    if not install or install["id"] == FIRST:
        return folder
    return folder / "profiles" / install["id"]


def state_path(folder: pathlib.Path, install: dict | None) -> pathlib.Path:
    path = profile_folder(folder, install) / "state.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def backups_folder(folder: pathlib.Path, install: dict | None) -> pathlib.Path:
    return profile_folder(folder, install) / "addon-backups"


def client_info(game) -> dict:
    """{flavor, version, product, region} of a client folder; each None when unknown. The region is
    the Battle.net branch the client was installed for ("eu", "us", ...)."""
    game = pathlib.Path(str(game))
    info = {"flavor": game.name, "version": None, "product": None, "region": None}
    # an installation's .build.info lists every client in it: take the row of this folder's client
    wanted = {"_forever_": "wowf", "_retail_": "wow"}.get(game.name.lower())
    for path in (game / ".build.info", game.parent / ".build.info"):
        try:
            lines = path.read_text(encoding="utf-8-sig").splitlines()
        except OSError:
            continue
        if not lines:
            continue
        fields = [f.split("!")[0] for f in lines[0].split("|")]
        rows = [line.split("|") for line in lines[1:] if line.strip()]
        try:
            pi = fields.index("Product")
        except ValueError:
            continue
        vi = fields.index("Version") if "Version" in fields else None
        ai = fields.index("Active") if "Active" in fields else None
        bi = fields.index("Branch") if "Branch" in fields else None
        for row in rows:
            if len(row) <= pi or (ai is not None and (len(row) <= ai or row[ai] != "1")):
                continue
            if (row[pi] == wanted) if wanted else (row[pi] == "wowf" or len(rows) == 1):
                info["product"] = row[pi]
                if vi is not None and len(row) > vi:
                    info["version"] = row[vi] or None
                if bi is not None and len(row) > bi:
                    info["region"] = row[bi].strip().lower() or None
                return info
    return info


def describe(install: dict) -> str:
    """One line for the list: the folder, then the flavor and client version when known."""
    info = client_info(install["game"])
    extra = ", ".join(x for x in (info["flavor"], info["version"]) if x)
    return f'{install["game"]} ({extra})' if extra else install["game"]
