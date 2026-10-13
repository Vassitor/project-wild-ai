param(
    [string]$GodotPath = ''
)

# 每次 UI 验证使用新的工作区档案，不消费玩家货币或物资。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot executable not found. Pass -GodotPath.'
}
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
$taskProfileId = [Guid]::NewGuid().ToString('N')
Push-Location -LiteralPath $taskRoot
try {
    # 新增 class_name 后需要刷新全局类缓存，不能只检查旧缓存是否存在。
    & $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'p1-import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Project import failed.' }
    $taskImportLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p1-import.log') -Raw
    if ($taskImportLog -match 'SCRIPT ERROR|Parse Error') { throw 'Project import reported script errors.' }
    & $GodotPath --headless --path $taskRoot --script res://tests/p1_checks.gd --log-file (Join-Path $taskVerification 'p1-checks.log') -- "--profile-store=res://.godot/verification/p1_ui_$taskProfileId.cfg"
    if ($LASTEXITCODE -ne 0) { throw 'P1 checks failed.' }
    $taskLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p1-checks.log') -Raw
    if ($taskLog -match 'SCRIPT ERROR|Parse Error' -or $taskLog -notmatch 'P1 checks: \d+ passed, 0 failed') {
        throw 'P1 checks did not finish successfully.'
    }
}
finally {
    Pop-Location
}
