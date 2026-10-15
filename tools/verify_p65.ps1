param([string]$GodotPath = '', [int]$FaultRttMs = 100, [int]$DropEvery = 100, [switch]$SkipImport, [switch]$NetworkOnly)
# 四个真实进程，仅绑定回环；所有身份、个人 / 世界日志都在随机工作区目录。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools\godot\Godot_v4.7.2-stable_win64_console.exe' }
$taskVerification = Join-Path $taskRoot '.godot\verification'
New-Item -ItemType Directory -Path $taskVerification -Force | Out-Null
if (-not $SkipImport) {
    & $GodotPath --headless --editor --import --quit --path $taskRoot --log-file (Join-Path $taskVerification 'p65-import.log')
    if ($LASTEXITCODE -ne 0 -or (Get-Content -LiteralPath (Join-Path $taskVerification 'p65-import.log') -Raw) -match 'SCRIPT ERROR|Parse Error') { throw 'Import failed.' }
}
if (-not $NetworkOnly) {
    foreach ($taskSuite in @('checks','ui_checks')) {
        $taskLog = Join-Path $taskVerification "p65-$taskSuite.log"
        & $GodotPath --headless --path $taskRoot --script "res://tests/p65_$taskSuite.gd" --log-file $taskLog
        $taskText = Get-Content -LiteralPath $taskLog -Raw
        if ($LASTEXITCODE -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use' -or $taskText -notmatch 'P6.5 (domain|UI) checks: \d+ passed, 0 failed') { throw "P6.5 $taskSuite failed." }
    }
}
$taskCases = @()
foreach ($taskFault in @(0,$FaultRttMs)) {
    $taskId = 'p65-' + [Guid]::NewGuid().ToString('N')
    $taskCase = Join-Path $taskVerification $taskId
    New-Item -ItemType Directory -Path $taskCase -Force | Out-Null
    $taskSocket = [Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Dgram, [Net.Sockets.ProtocolType]::Udp)
    $taskSocket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
    $taskPort = $taskSocket.LocalEndPoint.Port
    $taskSocket.Close()
    $taskProcesses = @{}
    try {
        $taskCommon = @('--headless','--max-fps','60','--path',('"'+$taskRoot+'"'),'res://tests/p65_network.tscn','--log-file')
        foreach ($taskRole in @('p0','p1','p2','p3')) {
            $taskArgs = $taskCommon + @(('"'+(Join-Path $taskCase "$taskRole.log")+'"'),'--',"--role=$taskRole","--port=$taskPort","--case-root=res://.godot/verification/$taskId","--fault=$taskFault", "--drop-every=$DropEvery")
            $taskProcesses[$taskRole] = Start-Process -FilePath $GodotPath -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru
            if ($taskRole -eq 'p0') {
                $taskReadyDeadline = [DateTime]::UtcNow.AddSeconds(25)
                while (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt')) -and [DateTime]::UtcNow -lt $taskReadyDeadline -and -not $taskProcesses.p0.HasExited) { Start-Sleep -Milliseconds 100 }
                if (-not (Test-Path -LiteralPath (Join-Path $taskCase 'ready.txt'))) { throw "Server did not start: $taskCase" }
            }
        }
        $taskDeadline = [DateTime]::UtcNow.AddSeconds(450)
        $taskRestarted = $false
        while ([DateTime]::UtcNow -lt $taskDeadline) {
            if ($taskFault -gt 0 -and -not $taskRestarted -and $taskProcesses.p0.HasExited -and (Test-Path -LiteralPath (Join-Path $taskCase 'p0-before-restart-result.json'))) {
                $taskBefore = Get-Content -LiteralPath (Join-Path $taskCase 'p0-before-restart-result.json') -Raw | ConvertFrom-Json
                if ($taskBefore.failed -ne 0) { throw "Host failed before restart: $taskCase" }
                $taskArgs = $taskCommon + @(('"'+(Join-Path $taskCase 'p0-restored.log')+'"'),'--','--role=p0',"--port=$taskPort","--case-root=res://.godot/verification/$taskId","--fault=$taskFault", "--drop-every=$DropEvery",'--resume')
                $taskProcesses.p0 = Start-Process -FilePath $GodotPath -ArgumentList $taskArgs -WorkingDirectory $taskRoot -WindowStyle Hidden -PassThru
                $taskRestarted = $true
            }
            $taskAlive = @($taskProcesses.Values | Where-Object { -not $_.HasExited })
            if ($taskAlive.Count -eq 0) { break }
            Start-Sleep -Milliseconds 250
        }
        foreach ($taskRole in @('p0','p1','p2','p3')) {
            $taskResultPath = Join-Path $taskCase "$taskRole-result.json"
            if (-not (Test-Path -LiteralPath $taskResultPath)) { throw "Missing $taskRole result: $taskCase" }
            $taskResult = Get-Content -LiteralPath $taskResultPath -Raw | ConvertFrom-Json
            $taskLogs = @((Join-Path $taskCase "$taskRole.log"))
            if ($taskRole -eq 'p0' -and $taskRestarted) { $taskLogs += Join-Path $taskCase 'p0-restored.log' }
            $taskText = ($taskLogs | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join "`n"
            if ($taskResult.failed -ne 0 -or $taskText -match 'SCRIPT ERROR|Parse Error|ERROR:|leaked|still in use') { throw "P6.5 ENet $taskRole failed: $taskCase" }
            Write-Output "P6.5 ENet $taskRole, RTT ${taskFault}ms: $($taskResult.passed) passed; drops $($taskResult.dropped_packets), retries $($taskResult.retransmissions)"
        }
        $taskCases += $taskCase
    } finally {
        foreach ($taskProcess in $taskProcesses.Values) { if (-not $taskProcess.HasExited) { Stop-Process -Id $taskProcess.Id } }
    }
}
$taskCases | Set-Content -LiteralPath (Join-Path $taskVerification 'p65-latest-cases.txt') -Encoding utf8
Write-Output 'P6.5 full lifecycle verification completed; four loopback processes / isolated personal and world saves.'
