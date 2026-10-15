param([string]$GodotPath = '', [switch]$SkipImport)
# P7 只运行随机工作区档案和内存夹具；不读取正式游戏身份 / 基地。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
if (-not $SkipImport) {
    & $GodotPath --headless --editor --import --quit --path $taskRoot --log-file (Join-Path $taskVerification 'p7-import.log')
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskVerification 'p7-import.log') -Raw) -match 'SCRIPT ERROR|Parse Error') { throw 'P7 import failed.' }
}
foreach ($taskCase in @(@{Script='p7_checks.gd'; Log='p7-checks.log'; Expected='P7 integration checks: \d+ passed, 0 failed'},@{Script='p7_ui_checks.gd'; Log='p7-ui-checks.log'; Expected='P7 UI checks: \d+ passed, 0 failed'})) {
    & $GodotPath --headless --path $taskRoot --script ('res://tests/' + $taskCase.Script) --log-file (Join-Path $taskVerification $taskCase.Log)
    $taskLog = Get-Content -LiteralPath (Join-Path $taskVerification $taskCase.Log) -Raw
    if ($LASTEXITCODE -ne 0 -or $taskLog -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use' -or $taskLog -notmatch $taskCase.Expected) { throw ('P7 verification failed: ' + $taskCase.Script) }
}
Write-Output 'P7 controlled food routes / economy / settlement / guide verified; isolated saves only.'
