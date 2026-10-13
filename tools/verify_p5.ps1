param([string]$GodotPath = '', [switch]$SkipImport)
# 真实双进程 ENet；每次随机端口 / 隔离档案，不访问正式身份与基地。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe' }
if (-not (Test-Path -LiteralPath $GodotPath)) { throw 'Godot executable not found.' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
if (-not $SkipImport) {
    & $GodotPath --headless --editor --import --path $taskRoot --log-file (Join-Path $taskVerification 'p5-import.log')
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskVerification 'p5-import.log') -Raw) -match 'SCRIPT ERROR|Parse Error') { throw 'Import failed.' }
}
& $GodotPath --headless --path $taskRoot --script res://tests/p5_checks.gd --log-file (Join-Path $taskVerification 'p5-checks.log')
$taskDomainLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p5-checks.log') -Raw
if ($LASTEXITCODE -ne 0 -or $taskDomainLog -match 'SCRIPT ERROR|Parse Error|leaked|still in use' -or $taskDomainLog -notmatch 'P5 domain checks: \d+ passed, 0 failed') { throw 'P5 domain checks failed.' }
& $GodotPath --headless --path $taskRoot --script res://tests/p5_ui_checks.gd --log-file (Join-Path $taskVerification 'p5-ui-checks.log')
$taskUiLog = Get-Content -LiteralPath (Join-Path $taskVerification 'p5-ui-checks.log') -Raw
if ($LASTEXITCODE -ne 0 -or $taskUiLog -match 'SCRIPT ERROR|Parse Error|leaked|still in use' -or $taskUiLog -notmatch 'P5 UI checks: \d+ passed, 0 failed') { throw 'UI checks failed.' }
$taskCases = @()
foreach ($taskFault in @(0,100)) {
    $taskId = 'p5-' + [Guid]::NewGuid().ToString('N')
    $taskCase = Join-Path $taskVerification $taskId
    New-Item -ItemType Directory -Path $taskCase -Force | Out-Null
    $taskSocket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
    $taskSocket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
    $taskPort = $taskSocket.LocalEndPoint.Port
    $taskSocket.Close()
    $taskHostProcess = $null
    $taskClientProcess = $null
    try {
        $taskCommon = @('--headless','--path', ('"' + $taskRoot + '"'), 'res://tests/p5_network.tscn', '--log-file')
        $taskHostArgs = $taskCommon + @(('"' + (Join-Path $taskCase 'host.log') + '"'),'--','--role=host',"--port=$taskPort", "--case-root=res://.godot/verification/$taskId", "--fault=$taskFault")
        $taskHostProcess = Start-Process -FilePath $GodotPath -ArgumentList $taskHostArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru
        $taskReadyDeadline = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt')) -and [DateTime]::UtcNow -lt $taskReadyDeadline -and -not $taskHostProcess.HasExited) { Start-Sleep -Milliseconds 100 }
        if (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt'))) { throw "Server did not start: $taskCase" }
        $taskClientArgs = $taskCommon + @(('"' + (Join-Path $taskCase 'client.log') + '"'),'--','--role=client',"--port=$taskPort", "--case-root=res://.godot/verification/$taskId", "--fault=$taskFault")
        $taskClientProcess = Start-Process -FilePath $GodotPath -ArgumentList $taskClientArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru
        $taskDeadline = [DateTime]::UtcNow.AddSeconds(130)
        while ((-not $taskHostProcess.HasExited -or -not $taskClientProcess.HasExited) -and [DateTime]::UtcNow -lt $taskDeadline) { Start-Sleep -Milliseconds 250 }
        foreach ($taskRole in @('host','client')) {
            $taskLog = Get-Content -LiteralPath (Join-Path $taskCase "$taskRole.log") -Raw
            $taskResult = Get-Content -LiteralPath (Join-Path $taskCase "$taskRole-result.json") -Raw | ConvertFrom-Json
            if ($taskResult.failed -ne 0 -or $taskLog -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use') { throw "ENet $taskRole failed ($taskFault ms): $taskCase" }
            Write-Output "ENet $taskRole, RTT ${taskFault}ms: $($taskResult.passed) passed; drops $($taskResult.dropped_packets), retries $($taskResult.retransmissions)"
        }
        $taskCases += $taskCase
    } finally {
        if ($taskHostProcess -and -not $taskHostProcess.HasExited) { Stop-Process -Id $taskHostProcess.Id }
        if ($taskClientProcess -and -not $taskClientProcess.HasExited) { Stop-Process -Id $taskClientProcess.Id }
    }
}
$taskCases | Set-Content -LiteralPath (Join-Path $taskVerification 'p5-latest-cases.txt') -Encoding utf8
Write-Output 'P5 skills / fishing / traps / real ENet verification completed; isolated saves only.'


