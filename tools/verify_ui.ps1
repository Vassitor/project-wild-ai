param([string]$GodotPath = '', [switch]$SkipImport)
# UI / 动画回归使用脚本内的随机工作区档案；合作组合根只绑定回环。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found.' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
if (-not $SkipImport) {
    $taskImportPath = Join-Path $taskVerification 'ui-import.log'
    & $GodotPath --headless --editor --import --path $taskRoot --log-file $taskImportPath
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath $taskImportPath -Raw) -match 'SCRIPT ERROR|Parse Error') { throw 'UI import failed.' }
}
foreach ($taskCheck in @('ui_layout_checks','p5_ui_checks','p4_ui_checks','p35_ui_checks','ninja_art_checks')) {
    $taskLogPath = Join-Path $taskVerification "ui-$taskCheck.log"
    & $GodotPath --headless --path $taskRoot --script "res://tests/$taskCheck.gd" --log-file $taskLogPath
    $taskLog = Get-Content -LiteralPath $taskLogPath -Raw
    if ($LASTEXITCODE -ne 0 -or $taskLog -match 'SCRIPT ERROR|Parse Error|leaked|still in use' -or $taskLog -notmatch 'checks: \d+ passed, 0 failed') {
        throw "$taskCheck did not complete successfully. See $taskLogPath"
    }
}
Write-Output 'UI layout / menu / Ninja animation verification completed; isolated saves only.'
