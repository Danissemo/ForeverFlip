"""Register the reviewed portable toolchain without replacing unrelated config."""
import datetime
import json
from pathlib import Path
import shutil
import tomllib

def copy_skill(source, destination):
    """Registered skill directories may already point into this workspace."""
    if destination.exists() and source.samefile(destination):
        return False
    shutil.copy2(source, destination)
    return True

root = Path(__file__).resolve().parent.parent
installed = json.loads((root / '.tools/installed.json').read_text(encoding='utf-8-sig'))
codex = Path.home() / '.codex'
config = codex / 'config.toml'
original = config.read_text(encoding='utf-8') if config.exists() else ''
parsed = tomllib.loads(original)
node = Path(installed['nodeDirectory']) / 'node.exe'
server = root / '.tools/mcp/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js'
if not node.is_file() or not server.is_file():
    raise SystemExit('Complete toolchain installation first.')
paths = [root, Path(installed['gamePath']) / 'Interface/AddOns', Path(installed['gamePath']) / 'Logs']
if not all(p.is_dir() for p in paths):
    raise SystemExit('An allowed MCP directory is missing.')
entry = {
    'command': node.as_posix(),
    'args': [server.as_posix(), '--read-only', '--confine-roots', *[p.as_posix() for p in paths]],
    'startup_timeout_sec': 60,
    'disabled_tools': ['write_file', 'edit_file', 'create_directory', 'move_file'],
}
existing = parsed.get('mcp_servers', {}).get('wow_forever_files')
legacy = dict(entry, args=[server.as_posix(), *[p.as_posix() for p in paths]])
if existing == legacy:
    original = original.replace('args = ' + json.dumps(legacy['args'], ensure_ascii=False),
                                'args = ' + json.dumps(entry['args'], ensure_ascii=False))
    existing = entry
if existing is not None and existing != entry:
    raise SystemExit('A different wow_forever_files config already exists; review before replacing.')
addition = '\n\n[mcp_servers.wow_forever_files]\n'
for key, value in entry.items():
    addition += key + ' = ' + json.dumps(value, ensure_ascii=False) + '\n'
updated = original if existing else original.rstrip() + addition
tomllib.loads(updated)
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = root / '.tools/backups' / stamp
backup.mkdir(parents=True, exist_ok=True)
if config.exists():
    shutil.copy2(config, backup / 'config.toml')
skill = codex / 'skills/wow-forever-addons/SKILL.md'
skill.parent.mkdir(parents=True, exist_ok=True)
if skill.exists():
    shutil.copy2(skill, backup / 'SKILL.md')
copy_skill(root / 'setup/skills/wow-forever-addons/SKILL.md', skill)
config.write_text(updated, encoding='utf-8')
assert tomllib.loads(config.read_text(encoding='utf-8'))['mcp_servers']['wow_forever_files'] == entry
print('Registered wow_forever_files (write/edit/create/move tools disabled).')
print('Installed skill:', skill)
print('Configuration backup:', backup)
print('Restart Codex or open a new session to load the MCP and skill.')
