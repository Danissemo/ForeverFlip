$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $root '.tools'
$downloads = Join-Path $tools 'downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
$ProgressPreference = 'SilentlyContinue'
$manifest = [ordered]@{}
$locked = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain-lock.json') -Raw | ConvertFrom-Json
function Download($url, $name) {
    $target = Join-Path $downloads $name
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "Downloading $name"
        Invoke-WebRequest -Uri $url -OutFile $target -TimeoutSec 300
    }
    return $target
}

# Node includes npm; verify the official distribution before extracting.
$node = @{ version = $locked.node }
$nodeName = "node-$($node.version)-win-x64"
$nodeZip = Download "https://nodejs.org/dist/$($node.version)/$nodeName.zip" "$nodeName.zip"
$checksums = (Invoke-WebRequest "https://nodejs.org/dist/$($node.version)/SHASUMS256.txt").Content
$expected = (($checksums -split "`n" | Where-Object { $_ -match " $([regex]::Escape($nodeName)).zip\s*$" }) -split '\s+')[0]
if (-not $expected -or (Get-FileHash $nodeZip -Algorithm SHA256).Hash -ne $expected) { throw 'Node checksum mismatch' }
if (-not (Test-Path "$tools/$nodeName/node.exe")) { Expand-Archive $nodeZip $tools -Force }
$nodeDir = Join-Path $tools $nodeName
$env:PATH = "$nodeDir;$env:PATH"
$manifest.node = $node.version

$luaVersion = $locked.luals
$archive = Download "https://github.com/LuaLS/lua-language-server/releases/download/$luaVersion/lua-language-server-$luaVersion-win32-x64.zip" 'luals.zip'
if (-not (Test-Path "$tools/luals/bin/lua-language-server.exe")) { Expand-Archive $archive "$tools/luals" -Force }
$manifest.luals = $luaVersion
$archive = Download 'https://github.com/JohnnyMorganz/StyLua/releases/download/v2.6.0/stylua-windows-x86_64.zip' 'stylua.zip'
if (-not (Test-Path "$tools/stylua/stylua.exe")) { Expand-Archive $archive "$tools/stylua" -Force }
$manifest.stylua = '2.6.0'

$archive = Download "https://update.code.visualstudio.com/$($locked.vscode)/win32-x64-archive/stable" "vscode-$($locked.vscode).zip"
if (-not (Test-Path "$tools/vscode/Code.exe")) { Expand-Archive $archive "$tools/vscode" -Force }
New-Item -ItemType Directory -Force "$tools/vscode/data" | Out-Null
foreach ($extension in $locked.extensions.PSObject.Properties) {
    & "$tools/vscode/bin/code.cmd" --install-extension "$($extension.Name)@$($extension.Value)"
    if ($LASTEXITCODE -ne 0) { throw "Extension installation failed: $($extension.Name)" }
}

New-Item -ItemType Directory -Force "$tools/mcp" | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'mcp-package-lock.json') -Destination "$tools/mcp/package-lock.json" -Force
$mcpLock = Get-Content -LiteralPath "$tools/mcp/package-lock.json" -Raw | ConvertFrom-Json
@{ dependencies = $mcpLock.packages.''.dependencies } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$tools/mcp/package.json" -Encoding utf8
& "$nodeDir/npm.cmd" ci --prefix "$tools/mcp" --ignore-scripts --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'MCP installation failed' }

$python = 'C:/Users/ARESTO/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
if (-not (Test-Path "$tools/python/Scripts/python.exe")) { & $python -m venv "$tools/python" }
$requirements = Join-Path $root 'development/foreverflip/requirements-dev.txt'
& "$tools/python/Scripts/python.exe" -m pip install --disable-pip-version-check --requirement $requirements
if ($LASTEXITCODE -ne 0) { throw 'Lua runtime installation failed' }

$reference = Join-Path $root 'references/wow-ui-source'
if (-not (Test-Path "$reference/.git")) {
    git clone --depth 1 --branch forever --single-branch https://github.com/Gethe/wow-ui-source.git $reference
    if ($LASTEXITCODE -ne 0) { throw 'Forever UI source download failed' }
}
$manifest.uiCommit = (git -C $reference rev-parse HEAD)
if ($manifest.uiCommit -ne $locked.uiCommit) {
    throw 'UI reference differs from toolchain-lock.json; preserve local changes and check out the locked commit before continuing.'
}
$manifest.uiBranch = 'forever'
$manifest.installedAt = (Get-Date).ToString('o')
$manifest.gamePath = 'C:/World of Warcraft/_forever_'
$manifest.clientVersion = '1.60.1.70862'
$manifest.interface = 16001
$manifest.nodeDirectory = $nodeDir
$manifest | ConvertTo-Json | Set-Content "$tools/installed.json" -Encoding utf8
Write-Host 'Toolchain installation completed.'
