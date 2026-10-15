param([switch]$SkipSmoke)
# 发布模板禁用外部 --script；使用候选专属入口，所有写入限定在 EXE 旁 qa 子目录。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskExecutable = Join-Path $taskRoot 'build/windows/WildBetween.exe'
$taskCase = Join-Path $taskRoot ('build/windows/qa/p8-export-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskCase -Force | Out-Null
$taskSocket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$taskSocket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
$taskPort = $taskSocket.LocalEndPoint.Port
$taskSocket.Close()
$taskProcesses = @{}
function Start-Probe([string]$taskRole) {
    $taskArgs = @('--headless','--log-file',('"'+(Join-Path $taskCase "$taskRole.log")+'"'),'--','--qa-probe',('--case-root="'+$taskCase+'"'),"--role=$taskRole","--port=$taskPort")
    return Start-Process -FilePath $taskExecutable -ArgumentList $taskArgs -WorkingDirectory (Split-Path $taskExecutable) -WindowStyle Hidden -PassThru
}
try {
    if (-not $SkipSmoke) {
        $taskProcesses.smoke = Start-Probe 'smoke'
        if (-not $taskProcesses.smoke.WaitForExit(60000) -or $taskProcesses.smoke.ExitCode -ne 0) { throw 'Export smoke process failed' }
    }
    $taskProcesses.host = Start-Probe 'host'
    $taskReady = [DateTime]::UtcNow.AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt')) -and [DateTime]::UtcNow -lt $taskReady -and -not $taskProcesses.host.HasExited) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt'))) { throw 'Export host failed to start' }
    $taskProcesses.client = Start-Probe 'client'
    $taskDeadline = [DateTime]::UtcNow.AddMinutes(7)
    while (@($taskProcesses.Values | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $taskDeadline) { Start-Sleep -Milliseconds 250 }
    foreach ($taskRole in $taskProcesses.Keys) {
        $taskText = Get-Content -LiteralPath (Join-Path $taskCase "$taskRole.log") -Raw
        $taskResult = Get-Content -LiteralPath (Join-Path $taskCase "$taskRole-result.json") -Raw | ConvertFrom-Json
        if (-not $taskProcesses[$taskRole].HasExited -or $taskProcesses[$taskRole].ExitCode -ne 0 -or $taskResult.failed -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use') { throw "Export $taskRole checks failed: $taskCase" }
        Write-Output "Export $taskRole checks: $($taskResult.passed) passed"
    }
    Set-Content -LiteralPath (Join-Path $taskRoot '.godot/verification/p8-export-latest.txt') -Value $taskCase -Encoding utf8
} finally { foreach ($taskProcess in $taskProcesses.Values) { if (-not $taskProcess.HasExited) { Stop-Process -Id $taskProcess.Id } } }
