"""Test and package the reviewed addon without touching the game installation."""
import argparse
import hashlib
import json
import re
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
allowed={'.lua','.toc','.md','.txt','.json','.py'}
source_files=[(p,Path('ForeverFlip-source')/p.relative_to(repo))for p in repo.rglob('*')
    if p.is_file()and p.suffix in allowed and not any(part in {'.git','dist','__pycache__'}for part in p.relative_to(repo).parts)]
report={'client':'1.60.1.70862','interface':16001,'lua':'5.1','compiled_modules':len(modules),
    'tests':'passed; see tests.txt','live_client_tested':False,
    'artifacts':[archive(package,addon_files),archive(source,source_files)]}
(out/'build-report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
