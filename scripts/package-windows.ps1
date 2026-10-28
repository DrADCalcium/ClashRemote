param(
    [ValidateSet('debug','release')][string]$Configuration='debug',
    [switch]$SkipBuild,
    [string]$SwiftRuntimePath=(Join-Path $env:LOCALAPPDATA 'Programs\Swift\Runtimes\6.4.1\usr\bin'),
    [string]$RuntimeInstaller
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if(-not $SkipBuild){& (Join-Path $PSScriptRoot 'build-windows.ps1') -Configuration $Configuration}
$build=Join-Path $root ".build-crossui\x86_64-unknown-windows-msvc\$Configuration"
if(-not(Test-Path -LiteralPath (Join-Path $build 'ClashRemote.exe'))){throw 'Build the Windows x64 app first'}
if(-not(Test-Path -LiteralPath (Join-Path $SwiftRuntimePath 'swiftCore.dll'))){throw 'Specify the Swift runtime DLL directory with -SwiftRuntimePath'}
$output=Join-Path $root 'dist\ClashRemote-SwiftCrossUI-win-x64'
New-Item -ItemType Directory -Path $output -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $build 'ClashRemote.exe') -Destination $output -Force
$strip=Get-Command llvm-strip -ErrorAction SilentlyContinue
if($strip){
    & $strip.Source --strip-debug (Join-Path $output 'ClashRemote.exe')
    if($LASTEXITCODE -ne 0){throw 'Could not strip debug information'}
}
foreach($name in @('ClashRemote_ClashRemote.resources','swift-winui_CWinAppSDK.resources')){
    $source=Join-Path $build $name
    if(-not(Test-Path -LiteralPath $source)){throw "Missing resource bundle: $name"}
    $destination=Join-Path $output $name
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Get-ChildItem -LiteralPath $source | Copy-Item -Destination $destination -Recurse -Force
}
Get-ChildItem -LiteralPath $SwiftRuntimePath -Filter '*.dll' | Copy-Item -Destination $output -Force
$licenses=Join-Path $output 'licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination (Join-Path $licenses 'ClashRemote-LICENSE') -Force
$checkouts=Join-Path $root '.build-crossui\checkouts'
Get-ChildItem -LiteralPath $checkouts -Directory | ForEach-Object {
    $dependency=$_
    Get-ChildItem -LiteralPath $dependency.FullName -File |
        Where-Object {$_.Name -match '^(LICENSE|COPYING|NOTICE|COPYRIGHT)(\.|$)'} |
        ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $licenses ($dependency.Name+'-'+$_.Name)) -Force}
}
$swiftLicense=Join-Path $root 'docs\windows\Swift-LICENSE.txt'
if(Test-Path -LiteralPath $swiftLicense){Copy-Item -LiteralPath $swiftLicense -Destination (Join-Path $licenses 'Swift-LICENSE.txt') -Force}
Copy-Item -LiteralPath (Join-Path $root 'WINDOWS-CROSSUI.md') -Destination (Join-Path $output 'README.md') -Force
if($RuntimeInstaller){
    $signature=Get-AuthenticodeSignature -LiteralPath $RuntimeInstaller
    if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notlike '*Microsoft Corporation*'){
        throw 'Windows App Runtime installer must have a valid Microsoft signature'
    }
    $prerequisites=Join-Path $output 'prerequisites'
    New-Item -ItemType Directory -Path $prerequisites -Force | Out-Null
    Copy-Item -LiteralPath $RuntimeInstaller -Destination (Join-Path $prerequisites 'windowsappruntimeinstall-x64.exe') -Force
}
$archive=Join-Path $root 'dist\ClashRemote-SwiftCrossUI-win-x64.zip'
Compress-Archive -LiteralPath $output -DestinationPath $archive -Force -CompressionLevel Optimal
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Format-List
Write-Output $archive
