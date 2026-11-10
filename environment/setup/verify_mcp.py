"""Exercise the installed MCP over its real stdio transport, without writes."""
import json
from pathlib import Path
import queue
import subprocess
import threading
import tomllib

root = Path(__file__).resolve().parent.parent
config = tomllib.loads((Path.home() / '.codex/config.toml').read_text(encoding='utf-8'))
entry = config['mcp_servers']['wow_forever_files']
process = subprocess.Popen([entry['command'], *entry['args']], stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, encoding='utf-8')
messages = queue.Queue()

def receive():
    for line in process.stdout:
        messages.put(json.loads(line))

threading.Thread(target=receive, daemon=True).start()
counter = 0

def send(message):
    process.stdin.write(json.dumps({'jsonrpc': '2.0', **message}) + '\n')
    process.stdin.flush()

def request(method, params):
    global counter
    counter += 1
    send({'id': counter, 'method': method, 'params': params})
    while True:
        response = messages.get(timeout=20)
        if response.get('id') == counter:
            assert 'error' not in response, response
            return response['result']

try:
    result = request('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
        'clientInfo': {'name': 'forever-environment-verification', 'version': '1.0.0'}})
    print('PASS MCP initialize:', result['serverInfo']['name'])
    send({'method': 'notifications/initialized'})
    tools = request('tools/list', {})['tools']
    names = {tool['name'] for tool in tools}
    assert {'read_text_file', 'list_directory', 'list_allowed_directories'} <= names, names
    assert not names & {'write_file', 'edit_file', 'create_directory', 'move_file'}, names
    print('PASS read-only catalog:', len(names), 'tools')
    allowed = request('tools/call', {'name': 'list_allowed_directories', 'arguments': {}})
    assert not allowed.get('isError'), allowed
    assert 'AddOns' in str(allowed), allowed
    print('PASS allowed directories')
    toc = 'C:/World of Warcraft/_forever_/Interface/AddOns/GatherPathForever/GatherPathForever.toc'
    result = request('tools/call', {'name': 'read_text_file', 'arguments': {'path': toc}})
    assert not result.get('isError') and '16001' in str(result), result
    print('PASS real addon TOC read')
    result = request('tools/call', {'name': 'read_text_file',
        'arguments': {'path': 'C:/Windows/win.ini'}})
    assert result.get('isError'), result
    print('PASS access outside allowed directories rejected')
finally:
    process.terminate()
    process.wait(timeout=10)
