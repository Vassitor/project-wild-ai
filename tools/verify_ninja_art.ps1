param([string]$GodotPath = '')
# 只验证表现适配；测试自己创建随机工作区档案，不接触正式身份与存档。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found. Pass -GodotPath.' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
& $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'ninja-import.log')
if ($LASTEXITCODE -ne 0) { throw 'Import failed.' }
$taskImport = Get-Content -LiteralPath (Join-Path $taskVerification 'ninja-import.log') -Raw
if ($taskImport -match 'SCRIPT ERROR|Parse Error') { throw 'Import reported script errors.' }
& $GodotPath --headless --path $taskRoot --script res://tests/ninja_art_checks.gd --log-file (Join-Path $taskVerification 'ninja-art-checks.log')
if ($LASTEXITCODE -ne 0) { throw 'Ninja art checks failed.' }
$taskLog = Get-Content -LiteralPath (Join-Path $taskVerification 'ninja-art-checks.log') -Raw
if ($taskLog -match 'SCRIPT ERROR|Parse Error' -or $taskLog -notmatch 'Ninja art checks: \d+ passed, 0 failed') {
    throw 'Ninja art checks did not finish successfully.'
}
