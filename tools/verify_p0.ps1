param(
    [string]$GodotPath = ''
)

# 只操作工作区验证文件，正式游戏身份和存档不参与测试。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot executable not found. Pass -GodotPath with the editor executable path.'
}
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
Push-Location -LiteralPath $taskRoot
try {
    # 首次运行先建立 Godot 全局类与资源缓存，已有缓存时直接执行验证。
    if (-not (Test-Path -LiteralPath '.godot\global_script_class_cache.cfg')) {
        & $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'import.log')
        if ($LASTEXITCODE -ne 0) { throw 'Godot project import failed.' }
    }
    & $GodotPath --headless --path $taskRoot --script res://tests/p0_checks.gd --log-file (Join-Path $taskVerification 'checks.log') -- --profile-store=res://.godot/verification/checks_profile.cfg
    if ($LASTEXITCODE -ne 0) { throw 'P0 checks failed.' }
    $taskLog = Get-Content -LiteralPath (Join-Path $taskVerification 'checks.log') -Raw
    if ($taskLog -match 'SCRIPT ERROR|Parse Error' -or $taskLog -notmatch 'P0 checks: \d+ passed, 0 failed') {
        throw 'The engine reported script errors or did not finish the check suite.'
    }
}
finally {
    Pop-Location
}
