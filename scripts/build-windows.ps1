param([ValidateSet('debug','release')][string]$Configuration='debug', [switch]$Tests, [switch]$CoreChecks, [int]$Jobs=4)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if(-not(Test-Path -LiteralPath $vswhere)){throw 'Visual Studio C++ Build Tools are required'}
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vs){throw 'Visual Studio Desktop C++ workload is required'}
$dev=Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
$variables=& $env:ComSpec /d /c "call `"$dev`" -arch=x64 -host_arch=x64 >nul && set"
foreach($line in $variables){if($line -match '^([^=]+)=(.*)$'){[Environment]::SetEnvironmentVariable($matches[1],$matches[2],'Process')}}
foreach($name in @('SDKROOT','DEVELOPER_DIR')){
    if(-not [Environment]::GetEnvironmentVariable($name,'Process')){
        $value=[Environment]::GetEnvironmentVariable($name,'User')
        if(-not $value){$value=[Environment]::GetEnvironmentVariable($name,'Machine')}
        if($value){[Environment]::SetEnvironmentVariable($name,$value,'Process')}
    }
}
$swiftPaths=([Environment]::GetEnvironmentVariable('Path','User') -split ';' | Where-Object {$_ -match 'Swift' -and (Test-Path -LiteralPath $_)}) -join ';'
if($swiftPaths){$env:PATH=$swiftPaths+';'+$env:PATH}
if(-not(Get-Command swift -ErrorAction SilentlyContinue)){
    $roots=@((Join-Path $env:LOCALAPPDATA 'Programs\Swift\Toolchains'),'C:\Library\Developer\Toolchains')
    $compiler=Get-ChildItem -LiteralPath $roots -Filter swift.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $compiler){throw 'Install the official Swift Windows toolchain from swift.org first'}
    $env:PATH=$compiler.Directory.FullName+';'+$env:PATH
}
Push-Location $root
try {
    swift --version
    if($CoreChecks -or $Tests){
        swift test --build-system native --scratch-path .build-crossui -c $Configuration -j $Jobs --filter PlatformTests 2>&1 | Tee-Object -FilePath windows-core-tests.log
    } else {
        swift build --build-system native --scratch-path .build-crossui --product ClashRemote -c $Configuration -j $Jobs 2>&1 | Tee-Object -FilePath windows-crossui-build.log
    }
    if($LASTEXITCODE -ne 0){throw 'Swift build or tests failed; inspect the build log'}
} finally {Pop-Location}
