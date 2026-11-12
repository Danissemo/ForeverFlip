"""Build the Windows Sync helper and verify its actual frozen TLS/Tk runtime."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import ssl
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT/'dist')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Build the Windows helper on Windows')
    output = args.output.resolve()
    work = output/'helper-build'
    work.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, '-m', 'PyInstaller', '--noconfirm', '--onefile', '--windowed',
               '--name', 'ForeverFlipSync', '--paths', str(ROOT/'sync'), '--distpath', str(output),
               '--workpath', str(work), '--specpath', str(work)]
    # Some Python distributions load this public rejection policy in SSLContext.__new__.
    # Bundle it unchanged next to frozen ssl.py; omitting it breaks even context creation.
    # Standard Python distributions do not require this additional resource.
    policy = pathlib.Path(ssl.__file__).with_name('codex-rejected-cas.pem')
    if policy.is_file():
        command += ['--add-data', f'{policy}{os.pathsep}.']
    command.append(str(ROOT/'sync/foreverflip_sync.py'))
    subprocess.run(command, cwd=ROOT, check=True)
    executable = output/'ForeverFlipSync.exe'
    with tempfile.TemporaryDirectory(prefix='ff-helper-check-') as folder:
        report = pathlib.Path(folder)/'runtime.json'
        subprocess.run([str(executable), '--self-test', '--self-test-report', str(report)],
                       check=True, timeout=45, creationflags=subprocess.CREATE_NO_WINDOW)
        result = json.loads(report.read_text(encoding='utf-8'))
        if not result.get('ok') or not result.get('tls_verified') or not result.get('gui_checked'):
            raise RuntimeError(f'Packaged helper runtime failed: {result}')
    print(f'Built {executable}; frozen TLS verification and Tk runtime passed.')


if __name__ == '__main__':
    main()
