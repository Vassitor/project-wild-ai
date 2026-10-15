param([string]$GodotPath = '')
# 候选包使用匹配的官方 Windows x64 模板；不启动正式游戏。
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($GodotPath)) { $GodotPath = Join-Path $taskRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe' }
$taskOutput = Join-Path $taskRoot 'build/windows'
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $taskRoot '.godot/verification') -Force | Out-Null
& $GodotPath --headless --path $taskRoot --script res://tools/build_metadata.gd --log-file (Join-Path $taskRoot '.godot/verification/p8-build-metadata.log')
if ($LASTEXITCODE -ne 0) { throw 'Build metadata failed' }
& $GodotPath --headless --path $taskRoot --export-release 'Windows Candidate' (Join-Path $taskOutput 'WildBetween.exe') --log-file (Join-Path $taskRoot '.godot/verification/p8-export.log')
$taskLog = Get-Content -LiteralPath (Join-Path $taskRoot '.godot/verification/p8-export.log') -Raw
if ($LASTEXITCODE -ne 0 -or $taskLog -match 'SCRIPT ERROR|Parse Error|ERROR:') { throw 'Windows export failed' }
Copy-Item -LiteralPath (Join-Path $taskRoot 'assets/ninja_adventure/LICENSE.txt') -Destination (Join-Path $taskOutput 'NINJA-ADVENTURE-CC0.txt') -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'assets/ninja_adventure/AUTHOR-README.md') -Destination (Join-Path $taskOutput 'NINJA-ADVENTURE-AUTHORS.md') -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'data/build_manifest.json') -Destination (Join-Path $taskOutput 'build_manifest.json') -Force
Write-Output ('Windows candidate exported: ' + $taskOutput)
