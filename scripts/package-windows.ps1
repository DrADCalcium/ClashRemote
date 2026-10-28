param(
    [ValidateSet('debug','release')][string]$Configuration='debug',
    [switch]$SkipBuild,
    [string]$SwiftRuntimePath=(Join-Path $env:LOCALAPPDATA 'Programs\Swift\Runtimes\6.4.1\usr\bin')
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $SkipBuild){& (Join-Path $PSScriptRoot 'build-windows.ps1') -Configuration $Configuration}
$build=Join-Path $root ".build\x86_64-unknown-windows-msvc\$Configuration"
if(-not(Test-Path -LiteralPath (Join-Path $build 'ClashRemote.exe'))){throw 'Build the Windows x64 app first'}
if(-not(Test-Path -LiteralPath (Join-Path $SwiftRuntimePath 'swiftCore.dll'))){throw 'Specify the Swift runtime DLL directory with -SwiftRuntimePath'}
$output=Join-Path $root 'dist\ClashRemote-SwiftOpenUI-win-x64'
# Refuse to mix stale resources or DLLs from an earlier build into a new package.
if(Test-Path -LiteralPath $output){throw "Move the existing package directory before rebuilding: $output"}
New-Item -ItemType Directory -Path $output -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'ClashRemote.exe') -Destination $output
$strip=Get-Command llvm-strip -ErrorAction SilentlyContinue
if($strip){
    & $strip.Source --strip-debug (Join-Path $output 'ClashRemote.exe')
    if($LASTEXITCODE -ne 0){throw 'Could not strip debug information'}
}
foreach($name in @('ClashRemote_ClashRemote.resources','SwiftOpenUI_SwiftOpenUISymbols.resources')){
    $source=Join-Path $build $name
    if(-not(Test-Path -LiteralPath $source)){throw "Missing resource bundle: $name"}
    Copy-Item -LiteralPath $source -Destination $output -Recurse
}
Get-ChildItem -LiteralPath $SwiftRuntimePath -Filter '*.dll' | Copy-Item -Destination $output
$licenses=Join-Path $output 'licenses'
New-Item -ItemType Directory -Path $licenses | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $licenses 'ClashRemote-LICENSE')
$dependency=$env:SWIFTOPENUI_PATH
if(-not $dependency){$dependency=Join-Path $root '.build\SwiftOpenUI-pinned'}
Copy-Item -LiteralPath (Join-Path $dependency 'LICENSE') -Destination (Join-Path $licenses 'SwiftOpenUI-LICENSE')
Copy-Item -LiteralPath (Join-Path $root 'docs\windows\Swift-LICENSE.txt') -Destination $licenses
Copy-Item -LiteralPath (Join-Path $root 'WINDOWS.md') -Destination (Join-Path $output 'README.md')
$archive=Join-Path $root 'dist\ClashRemote-SwiftOpenUI-win-x64.zip'
Compress-Archive -LiteralPath $output -DestinationPath $archive -Force -CompressionLevel Optimal
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Format-List
Write-Output $archive
