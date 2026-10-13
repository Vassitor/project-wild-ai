param([string]$GodotPath = '')
# 地图检查与真实场景共用隔离档案；不会打开正式存档。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found. Pass -GodotPath.' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
$taskProfileId = [Guid]::NewGuid().ToString('N')
& $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'p2-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Project import failed.' }
$taskImport = Get-Content -LiteralPath (Join-Path $taskVerification 'p2-import.log') -Raw
if ($taskImport -match 'SCRIPT ERROR|Parse Error') { throw 'Project import reported script errors.' }
& $GodotPath --headless --path $taskRoot --script res://tests/p2_checks.gd --log-file (Join-Path $taskVerification 'p2-checks.log') -- "--profile-store=res://.godot/verification/p2_ui_$taskProfileId.cfg"
if ($LASTEXITCODE -ne 0) { throw 'P2 checks failed.' }
$taskLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p2-checks.log') -Raw
if ($taskLog -match 'SCRIPT ERROR|Parse Error' -or $taskLog -notmatch 'P2 checks: \d+ passed, 0 failed') {
    throw 'P2 checks did not finish successfully.'
}
