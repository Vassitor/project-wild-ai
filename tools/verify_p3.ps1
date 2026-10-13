param([string]$GodotPath = '')
# P3 生存 / 存档 / UI 验证只使用随机工作区档案。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found. Pass -GodotPath.' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
& $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'p3-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Import failed.' }
$taskImport = Get-Content -LiteralPath (Join-Path $taskVerification 'p3-import.log') -Raw
if ($taskImport -match 'SCRIPT ERROR|Parse Error') { throw 'Import reported script errors.' }
& $GodotPath --headless --path $taskRoot --script res://tests/p3_checks.gd --log-file (Join-Path $taskVerification 'p3-checks.log')
if ($LASTEXITCODE -ne 0) { throw 'P3 checks failed.' }
$taskLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p3-checks.log') -Raw
if ($taskLog -match 'SCRIPT ERROR|Parse Error' -or $taskLog -notmatch 'P3 checks: \d+ passed, 0 failed') { throw 'P3 checks did not finish successfully.' }
