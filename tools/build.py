"""Test and package the reviewed addon without touching the game installation."""
import argparse
import hashlib
import json
import re
import os
import shutil
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
from lupa.lua51 import LuaRuntime

repo=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--output',default=str(repo/'dist'))
args=parser.parse_args()
out=Path(args.output).resolve();out.mkdir(parents=True,exist_ok=True)

def required_tool(variable, portable, command):
    value=os.environ.get(variable) or (str(portable) if portable.is_file() else shutil.which(command))
    if not value:
        raise SystemExit(f'Missing {command}: install the C:/FF toolchain or set {variable}.')
    return value

workspace=repo.parents[1]
stylua=required_tool('FF_STYLUA',workspace/'.tools/stylua/stylua.exe','stylua')
luals=required_tool('FF_LUALS',workspace/'.tools/luals/bin/lua-language-server.exe','lua-language-server')
style_config=workspace/'.stylua.toml'
if not style_config.is_file():
    style_config=repo/'.stylua.toml'
for name,command in [
    ('stylua',[stylua,'--check','--config-path',str(style_config),str(repo/'ForeverFlip')]),
    ('luals',[luals,'--check='+str(repo/'ForeverFlip'),'--configpath='+str(repo/'.luarc.json'),
              '--checklevel=Error','--logpath='+str(out/'luals')])]:
    checked=subprocess.run(command,cwd=repo,capture_output=True,text=True,encoding='utf-8')
    (out/(name+'.txt')).write_text(checked.stdout+'\n'+checked.stderr,encoding='utf-8')
    if checked.returncode:
        raise SystemExit(f'{name} failed; see {out/(name+".txt")}.')
tests=subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'tests'),'-v'],cwd=repo,
    capture_output=True,text=True,encoding='utf-8')
(out/'tests.txt').write_text(tests.stdout+'\n'+tests.stderr,encoding='utf-8')
if tests.returncode:
    print(tests.stderr);raise SystemExit('Tests failed; package not generated.')
lua=LuaRuntime();compile_chunk=lua.eval('function(s,n) local f,e=loadstring(s,n); if not f then error(e) end end')
addon=repo/'ForeverFlip'
toc=(addon/'ForeverFlip.toc').read_text(encoding='utf-8')
modules=[line.strip() for line in toc.splitlines() if line.strip().endswith('.lua')]
assert set(modules)=={p.name for p in addon.glob('*.lua')},'TOC/module mismatch'
for name in modules: compile_chunk((addon/name).read_text(encoding='utf-8'),name)
def archive(path,files):
    with ZipFile(path,'w',compression=ZIP_DEFLATED,compresslevel=9)as z:
        for file,relative in sorted(files,key=lambda pair:str(pair[1])):
            info=ZipInfo(str(relative).replace('\\','/'),date_time=(2026,11,9,0,0,0))
            info.compress_type=ZIP_DEFLATED;info.external_attr=0o644<<16
            z.writestr(info,file.read_bytes())
    with ZipFile(path)as z: assert z.testzip()is None
    return {'file':path.name,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
version=re.search(r'^## Version: ([A-Za-z0-9.\-]+)$',toc,re.M).group(1)
package=out/f'ForeverFlip-{version}-WoW-Forever.zip'
source=out/f'ForeverFlip-{version}-source.zip'
addon_files=[(p,Path('ForeverFlip')/p.relative_to(addon))for p in addon.rglob('*')if p.is_file()]
allowed={'.lua','.toc','.md','.txt','.json','.py','.ttf','.toml','.yml','.yaml','.ps1','.cmd'}
source_files=[(p,Path('ForeverFlip-source')/p.relative_to(repo))for p in repo.rglob('*')
    if p.is_file()and (p.suffix in allowed or p.name in {'.gitignore','.gitattributes'}) and not any(part in {'.git','dist','__pycache__','.superpowers'}for part in p.relative_to(repo).parts)]
source_hash=hashlib.sha256()
for file,relative in sorted(addon_files,key=lambda pair:str(pair[1])):
    source_hash.update(str(relative).encode());source_hash.update(file.read_bytes())
report={'client':'1.60.1.70862','interface':16001,'lua':'5.1','compiled_modules':len(modules),
    'version':version,'tests':'passed; see tests.txt',
    'test_count':int(re.search(r'Ran (\d+) tests?',tests.stderr).group(1)),
    'stylua':'passed','luals':'passed','source_sha256':source_hash.hexdigest(),'live_client_tested':False,
    'artifacts':[archive(package,addon_files),archive(source,source_files)]}
(out/'build-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
