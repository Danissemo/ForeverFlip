$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Split-Path $PSScriptRoot -Parent
$staging = Join-Path $root '.tools/debug-addons'
$destination = 'C:\World of Warcraft\_forever_\Interface\AddOns'
New-Item -ItemType Directory -Force $staging | Out-Null
$packages = @(
    @{ Name = '!BugGrabber'; File = '!BugGrabber-v12.1.1.zip'; Url = 'https://edge.forgecdn.net/files/9277/326/!BugGrabber-v12.1.1.zip'; MD5 = '737d6626decaca2ca59c79192c69d7ee' },
    @{ Name = 'BugSack'; File = 'BugSack-v12.1.9.zip'; Url = 'https://edge.forgecdn.net/files/9336/367/BugSack-v12.1.9.zip' }
)
foreach ($package in $packages) {
    $archive = Join-Path $staging $package.File
    Invoke-WebRequest $package.Url -OutFile $archive -TimeoutSec 90
    if ($package.MD5 -and (Get-FileHash $archive -Algorithm MD5).Hash -ne $package.MD5) { throw "Checksum mismatch: $($package.Name)" }
    $unpacked = Join-Path $staging $package.Name
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked -Force
    $addon = Join-Path $unpacked $package.Name
    $toc = Join-Path $addon "$($package.Name).toc"
    if (-not (Test-Path -LiteralPath $toc)) { throw "Missing TOC: $toc" }
    if (-not (Select-String -LiteralPath $toc -Pattern '^## Interface.*\b16001\b' -Quiet)) { throw "No Forever interface in $toc" }
    $target = Join-Path $destination $package.Name
    if (Test-Path -LiteralPath $target) { throw "Existing addon will not be overwritten: $target" }
    Copy-Item -LiteralPath $addon -Destination $destination -Recurse
    Write-Host "Installed $($package.Name) with verified Forever TOC."
}
