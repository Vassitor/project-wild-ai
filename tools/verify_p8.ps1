param([string]$GodotPath = '', [switch]$RealTimeSeeds, [switch]$Network, [switch]$Export)
# 默认运行本阶段针对性检查与同步保存基准；耗时的五种子默认速度测试显式选择。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' }
$taskVerify = Join-Path $taskRoot '.godot/verification'
New-Item -ItemType Directory -Path $taskVerify -Force | Out-Null
& $GodotPath --headless --editor --import --quit --path $taskRoot --log-file (Join-Path $taskVerify 'p8-import.log')
if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskVerify 'p8-import.log') -Raw) -match 'SCRIPT ERROR|Parse Error|ERROR:') { throw 'P8 import failed' }
foreach ($taskSuite in @('p8_checks','p8_benchmark')) {
    $taskLog = Join-Path $taskVerify ($taskSuite.Replace('_','-')+'.log')
    & $GodotPath --headless --path $taskRoot --script "res://tests/$taskSuite.gd" --log-file $taskLog
    $taskText = Get-Content -LiteralPath $taskLog -Raw
    $taskMarker = if ($taskSuite -eq 'p8_checks') { 'P8 checks: \d+ passed, 0 failed' } else { 'P8 benchmark ' }
    if ($LASTEXITCODE -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use' -or $taskText -notmatch $taskMarker) { throw "P8 $taskSuite failed" }
}
if ($RealTimeSeeds) {
    foreach ($taskSeed in @(17,18,7936,15855,31693)) {
        & $GodotPath --headless --path $taskRoot --script res://tests/p8_realtime.gd --log-file (Join-Path $taskVerify "p8-realtime-$taskSeed.log") -- "--seed=$taskSeed"
        $taskText = Get-Content -LiteralPath (Join-Path $taskVerify "p8-realtime-$taskSeed.log") -Raw
        if ($LASTEXITCODE -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use') { throw "Realtime seed $taskSeed failed" }
    }
}
if ($Network) { & (Join-Path $PSScriptRoot 'verify_p65.ps1') -GodotPath $GodotPath -SkipImport -FaultRttMs 150 -DropEvery 20 }
if ($Export) { & (Join-Path $PSScriptRoot 'build_windows.ps1') -GodotPath $GodotPath; & (Join-Path $PSScriptRoot 'verify_export.ps1') }
Write-Output 'P8 selected checks completed. Performance measurements are recorded, not asserted to meet the target.'
