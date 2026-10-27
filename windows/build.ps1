param([switch]$FrameworkDependent)
$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'ClashRemote.Windows/ClashRemote.Windows.csproj'
$out = Join-Path $PSScriptRoot 'artifacts/ClashRemote-win-x64'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_CLI_HOME = Join-Path $PSScriptRoot '.dotnet'
$env:NUGET_PACKAGES = Join-Path $PSScriptRoot '.nuget/packages'
dotnet run --project (Join-Path $PSScriptRoot 'ClashRemote.Tests') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Protocol checks failed' }
dotnet run --project (Join-Path $PSScriptRoot 'ClashRemote.WindowsChecks') -c Release
if ($LASTEXITCODE -ne 0) { throw 'Windows credential checks failed' }
$selfContained = if ($FrameworkDependent) { 'false' } else { 'true' }
dotnet publish $project -c Release -r win-x64 --self-contained $selfContained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $out
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }
Copy-Item (Join-Path $PSScriptRoot '../LICENSE') $out
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $out 'README-Windows.md')
Compress-Archive -Path (Join-Path $out '*') -DestinationPath (Join-Path $PSScriptRoot 'artifacts/ClashRemote-win-x64.zip') -Force
Get-FileHash (Join-Path $out 'ClashRemote.exe') -Algorithm SHA256
