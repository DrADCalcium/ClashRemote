param([ValidateSet('debug','release')][string]$Configuration='debug', [switch]$Tests, [switch]$CoreChecks)
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
    if($CoreChecks){
        $env:CLASHREMOTE_CORE_CHECKS='1'
        swift test --build-system native --scratch-path .build-core -c $Configuration 2>&1 | Tee-Object -FilePath (Join-Path $root 'windows-core-tests.log')
        if($LASTEXITCODE -ne 0){throw 'Swift Windows core checks failed; inspect windows-core-tests.log'}
        return
    }
    $env:CLASHREMOTE_CORE_CHECKS=$null
    if(-not $env:SWIFTOPENUI_PATH){
        $dependency=Join-Path $root '.build\SwiftOpenUI-pinned'
        if(-not(Test-Path -LiteralPath $dependency)){
            git clone --no-checkout https://github.com/codelynx/SwiftOpenUI.git $dependency
            if($LASTEXITCODE -ne 0){throw 'Could not download SwiftOpenUI'}
            git -C $dependency checkout 4afcacda74dec9e0bae18403c4427b05c8586943
            if($LASTEXITCODE -ne 0){throw 'Could not select the pinned SwiftOpenUI revision'}
        }
        $env:SWIFTOPENUI_PATH=$dependency
    }
    $revision=git -C $env:SWIFTOPENUI_PATH rev-parse HEAD
    if($LASTEXITCODE -ne 0 -or $revision -ne '4afcacda74dec9e0bae18403c4427b05c8586943'){throw 'SwiftOpenUI must use the pinned revision 4afcacd'}
    $patch=Join-Path $root 'patches\swiftopenui-swift64-winsdk.patch'
    git -C $env:SWIFTOPENUI_PATH apply --check $patch 2>$null
    if($LASTEXITCODE -eq 0){
        git -C $env:SWIFTOPENUI_PATH apply $patch
        if($LASTEXITCODE -ne 0){throw 'Could not patch SwiftOpenUI WinSDK headers'}
    } else {
        git -C $env:SWIFTOPENUI_PATH apply --reverse --check $patch 2>$null
        if($LASTEXITCODE -ne 0){throw 'SwiftOpenUI checkout does not match the expected WinSDK patch'}
    }
    swift build --build-system native -c $Configuration 2>&1 | Tee-Object -FilePath (Join-Path $root 'windows-build.log')
    if($LASTEXITCODE -ne 0){throw 'Swift Windows build failed; inspect windows-build.log'}
    if($Tests){swift test --build-system native -c $Configuration; if($LASTEXITCODE -ne 0){throw 'Swift tests failed'}}
} finally {Pop-Location}
