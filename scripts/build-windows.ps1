param(
    [ValidateSet('debug','release')][string]$Configuration='debug',
    [switch]$Tests,
    [switch]$CoreChecks,
    [switch]$APITests,
    [ValidateRange(1,64)][int]$Jobs=4
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
function Invoke-NativeTool {
    param([string]$Command, [string[]]$ToolArguments, [string]$LogPath, [switch]$Quiet)
    # Windows PowerShell 5.1 turns redirected native stderr into error records.
    # Let the native exit code decide success, including expected patch checks.
    $ErrorActionPreference='Continue'
    if($Quiet){ & $Command @ToolArguments *> $null }
    elseif($LogPath){ & $Command @ToolArguments 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $LogPath }
    else { & $Command @ToolArguments }
    $script:NativeExitCode=$LASTEXITCODE
}
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
        Invoke-NativeTool swift @('test','--build-system','native','--scratch-path','.build-core','-j',"$Jobs",'-c',$Configuration) -LogPath (Join-Path $root 'windows-core-tests.log')
        if($script:NativeExitCode -ne 0){throw 'Swift Windows core checks failed; inspect windows-core-tests.log'}
        return
    }
    $env:CLASHREMOTE_CORE_CHECKS=$null
    if(-not $env:SWIFTOPENUI_PATH){
        $dependency=Join-Path $root '.build\SwiftOpenUI-pinned'
        if(-not(Test-Path -LiteralPath $dependency)){
            Invoke-NativeTool git @('clone','--no-checkout','https://github.com/codelynx/SwiftOpenUI.git',$dependency)
            if($script:NativeExitCode -ne 0){throw 'Could not download SwiftOpenUI'}
            Invoke-NativeTool git @('-C',$dependency,'checkout','4afcacda74dec9e0bae18403c4427b05c8586943')
            if($script:NativeExitCode -ne 0){throw 'Could not select the pinned SwiftOpenUI revision'}
        }
        $env:SWIFTOPENUI_PATH=$dependency
    }
    $revision=git -C $env:SWIFTOPENUI_PATH rev-parse HEAD
    if($LASTEXITCODE -ne 0 -or $revision -ne '4afcacda74dec9e0bae18403c4427b05c8586943'){throw 'SwiftOpenUI must use the pinned revision 4afcacd'}
    foreach($patchName in @('swiftopenui-swift64-winsdk.patch','swiftopenui-windows-api.patch')){
        $patch=Join-Path $root ('patches\'+$patchName)
        Invoke-NativeTool git @('-C',$env:SWIFTOPENUI_PATH,'apply','--check',$patch) -Quiet
        if($script:NativeExitCode -eq 0){
            Invoke-NativeTool git @('-C',$env:SWIFTOPENUI_PATH,'apply',$patch)
            if($script:NativeExitCode -ne 0){throw "Could not apply SwiftOpenUI patch: $patchName"}
        } else {
            Invoke-NativeTool git @('-C',$env:SWIFTOPENUI_PATH,'apply','--reverse','--check',$patch) -Quiet
            if($script:NativeExitCode -ne 0){throw "SwiftOpenUI checkout does not match the expected patch: $patchName"}
        }
    }
    if($APITests){
        Invoke-NativeTool swift @('test','--build-system','native','--package-path','Tests/WindowsAPIChecks','--scratch-path','.build-api-tests','-j',"$Jobs",'-c',$Configuration) -LogPath (Join-Path $root 'windows-api-tests.log')
        if($script:NativeExitCode -ne 0){throw 'Windows API tests failed; inspect windows-api-tests.log'}
        return
    }
    Invoke-NativeTool swift @('build','--build-system','native','-j',"$Jobs",'-c',$Configuration) -LogPath (Join-Path $root 'windows-build.log')
    if($script:NativeExitCode -ne 0){throw 'Swift Windows build failed; inspect windows-build.log'}
    if($Tests){Invoke-NativeTool swift @('test','--build-system','native','-j',"$Jobs",'-c',$Configuration); if($script:NativeExitCode -ne 0){throw 'Swift tests failed'}}
} finally {Pop-Location}
