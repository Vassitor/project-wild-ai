# 显式列出交付文件，避免把 EXE 旁的 QA 身份、世界和日志一起打包。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskOutput = Join-Path $taskRoot 'build/windows'
$taskArchive = Join-Path $taskRoot 'build/WildBetween-0.2.0-rc1-windows-x64.zip'
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/20-candidate-player-guide.md') -Destination (Join-Path $taskOutput 'README-zh-CN.md') -Force
$taskLauncher = '@echo off' + "`r`n" + 'start "" "%~dp0WildBetween.exe" -- --profile-store=user://candidate_rc1_profile.cfg' + "`r`n"
[IO.File]::WriteAllText((Join-Path $taskOutput 'Play-Isolated.cmd'),$taskLauncher,[Text.Encoding]::ASCII)
$taskNames = @('WildBetween.exe','WildBetween.pck','WildBetween.console.exe','Play-Isolated.cmd','README-zh-CN.md','build_manifest.json','GODOT-LICENSE.txt','GODOT-THIRD-PARTY.json','NINJA-ADVENTURE-CC0.txt','NINJA-ADVENTURE-AUTHORS.md')
$taskFiles = @($taskNames | ForEach-Object { Join-Path $taskOutput $_ })
$taskSums = @($taskFiles | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($_) })
[IO.File]::WriteAllLines((Join-Path $taskOutput 'SHA256SUMS.txt'),$taskSums,[Text.UTF8Encoding]::new($false))
$taskFiles += Join-Path $taskOutput 'SHA256SUMS.txt'
Compress-Archive -LiteralPath $taskFiles -DestinationPath $taskArchive -CompressionLevel Optimal -Force
$taskHash = Get-FileHash -LiteralPath $taskArchive -Algorithm SHA256
[IO.File]::WriteAllText(($taskArchive+'.sha256'),$taskHash.Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($taskArchive)+"`n",[Text.UTF8Encoding]::new($false))
Write-Output ('Packaged: '+$taskArchive)
Write-Output ('SHA256: '+$taskHash.Hash.ToLowerInvariant())
