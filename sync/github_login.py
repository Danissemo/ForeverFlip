"""Signing in to GitHub from the Sync helper, without the GitHub CLI.

GitHub's device flow (the one the GitHub CLI uses): the helper asks GitHub for a short code, the
player enters it at github.com/login/device and approves, and the helper receives a token of the
ForeverFlip Sync GitHub App. The app's permissions are narrow: the player's gists (the upload) and
issues of the repositories it is installed on, which is only the community data repository (the
issue that points to the upload). Only the app's public client ID is built in; there is no client
secret. The app's tokens do not expire: Sign out, or revoke the app on GitHub, ends them.

The token is kept in the helper's folder, encrypted with Windows DPAPI: only the same Windows user
on the same computer can read it. Elsewhere the file is readable by its owner only.
"""

from __future__ import annotations

import json
import os
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

# The ForeverFlip Sync GitHub App (github.com/apps/foreverflip-sync); its client ID is public.
# config.json may give another as "client_id". A GitHub App ignores scopes: its permissions are set
# on the app; the scopes are kept for an OAuth app given in the config.
CLIENT_ID = "Iv23likzV28dBrdSnmFE"
SCOPES = "gist public_repo"
DEVICE_URL = "https://github.com/login/device/code"
TOKEN_URL = "https://github.com/login/oauth/access_token"
USER_URL = "https://api.github.com/user"
TOKEN_FILE = "github-token.bin"


class LoginError(RuntimeError):
    pass


def client_id(config: dict | None = None) -> str:
    return str((config or {}).get("client_id") or CLIENT_ID).strip()


def _post(url: str, fields: dict, agent: str) -> dict:
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", agent)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def start(cid: str, agent: str = "ForeverFlipSync") -> dict:
    """Asks GitHub for a device code: {device_code, user_code, verification_uri, interval, expires_in}."""
    if not cid:
        raise LoginError("signing in from the helper is not set up yet (no GitHub App client ID)")
    answer = _post(DEVICE_URL, {"client_id": cid, "scope": SCOPES}, agent)
    if "device_code" not in answer:
        raise LoginError(answer.get("error_description") or answer.get("error") or "GitHub gave no code")
    answer.setdefault("interval", 5)
    answer.setdefault("expires_in", 900)
    return answer


def wait_for_token(cid: str, device: dict, cancelled=lambda: False, sleep=time.sleep, clock=time.monotonic,
                   agent: str = "ForeverFlipSync") -> str:
    """Polls until the player approves (returns the token), declines, or the code expires."""
    interval = max(1, int(device.get("interval", 5)))
    deadline = clock() + int(device.get("expires_in", 900))
    while clock() < deadline:
        for _ in range(interval * 4):  # quarter-second steps, so cancelling is quick
            if cancelled():
                raise LoginError("signing in was cancelled")
            sleep(0.25)
        answer = _post(TOKEN_URL, {"client_id": cid, "device_code": device["device_code"],
                                   "grant_type": "urn:ietf:params:oauth:grant-type:device_code"}, agent)
        token = answer.get("access_token")
        if token:
            return token
        error = answer.get("error")
        if error == "authorization_pending":
            continue
        if error == "slow_down":
            interval = int(answer.get("interval") or interval + 5)
            continue
        if error == "expired_token":
            break
        if error == "access_denied":
            raise LoginError("access was not approved on GitHub")
        raise LoginError(answer.get("error_description") or error or "GitHub gave no token")
    raise LoginError("the code expired before it was entered; sign in again")


def whoami(token: str, agent: str = "ForeverFlipSync") -> str:
    req = urllib.request.Request(USER_URL)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("User-Agent", agent)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8")).get("login", "")


# --- Keeping the token -----------------------------------------------------------------------------

def _dpapi(data: bytes, protect: bool) -> bytes:
    import ctypes
    from ctypes import wintypes

    class Blob(ctypes.Structure):
        _fields_ = [("cbData", wintypes.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]

    crypt32, kernel32 = ctypes.windll.crypt32, ctypes.windll.kernel32
    buffer = ctypes.create_string_buffer(data, len(data))
    source = Blob(len(data), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_char)))
    result = Blob()
    entropy_bytes = b"ForeverFlipSync"
    entropy_buffer = ctypes.create_string_buffer(entropy_bytes, len(entropy_bytes))
    entropy = Blob(len(entropy_bytes), ctypes.cast(entropy_buffer, ctypes.POINTER(ctypes.c_char)))
    call = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
    flags = 0x1  # CRYPTPROTECT_UI_FORBIDDEN
    if protect:
        ok = call(ctypes.byref(source), "ForeverFlipSync", ctypes.byref(entropy), None, None, flags,
                  ctypes.byref(result))
    else:
        ok = call(ctypes.byref(source), None, ctypes.byref(entropy), None, None, flags, ctypes.byref(result))
    if not ok:
        raise OSError("Windows could not " + ("encrypt" if protect else "decrypt") + " the GitHub sign-in")
    try:
        return ctypes.string_at(result.pbData, result.cbData)
    finally:
        kernel32.LocalFree(result.pbData)


def save_token(folder: pathlib.Path, token: str) -> None:
    path = pathlib.Path(folder) / TOKEN_FILE
    data = token.encode("utf-8")
    if os.name == "nt":
        data = b"DPAPI1" + _dpapi(data, True)
    tmp = path.with_suffix(".tmp")
    tmp.write_bytes(data)
    if os.name != "nt":
        os.chmod(tmp, 0o600)
    tmp.replace(path)


def load_token(folder: pathlib.Path) -> str | None:
    path = pathlib.Path(folder) / TOKEN_FILE
    try:
        data = path.read_bytes()
    except OSError:
        return None
    try:
        if data.startswith(b"DPAPI1"):
            if os.name != "nt":
                return None
            data = _dpapi(data[6:], False)
        token = data.decode("utf-8").strip()
    except (OSError, UnicodeDecodeError):
        return None
    return token or None


def forget(folder: pathlib.Path) -> None:
    try:
        (pathlib.Path(folder) / TOKEN_FILE).unlink()
    except FileNotFoundError:
        pass
