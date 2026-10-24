function New-DiagnosticFolder([string]$label) {
    $directory = Join-Path $PatcherRoot ('logs/' + $label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    return $directory
}
function Copy-PlayerLogs([string]$destination, [string]$prefix) {
    $profile = Get-ProfileDir
    foreach ($name in @('Player.log', 'Player-prev.log', 'shutdown-timeout.log')) {
        $path = Join-Path $profile $name
        if (Test-Path -LiteralPath $path) {
            try { Copy-Item -LiteralPath $path -Destination (Join-Path $destination ($prefix + $name)) }
            catch { Write-Warn2 (T "Не удалось скопировать ${name}: $($_.Exception.Message)" "Could not copy ${name}: $($_.Exception.Message)") }
        }
    }
}
function Write-DiagnosticReport([string]$game, [string]$directory) {
    $report = New-Object 'System.Collections.Generic.List[string]'
    [void]$report.Add("SwyfPatcher $Version; time=$(Get-Date -Format o)")
    [void]$report.Add("Game: $game")
    [void]$report.Add("Q4 GPU profile: applied by the patched worker only for the verified Q4 hash + Vulkan0. GGUF weights stay unchanged; see qwen-worker logs for actual activation/device.")
    try {
        $ctx = Get-Context $game
        [void]$report.Add("Build table: $($ctx.Build.Tag); patched=$($ctx.Already); backend=$($ctx.CurVariant); reference=$($ctx.ReferenceSeconds)s; legacy=$($ctx.Legacy)")
    } catch { [void]$report.Add('Build check: ' + $_.Exception.Message) }
    $managed = Join-Path $game ($GameName + '_Data/Managed')
    foreach ($name in @('Assembly-CSharp.dll', 'ScriptsAssDef.dll', 'Kolkata.Speech.dll')) {
        $path = Join-Path $managed $name
        if (Test-Path -LiteralPath $path) { [void]$report.Add("DLL $name SHA256=$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)") }
        else { [void]$report.Add("MISSING DLL $name") }
    }
    try {
        foreach ($gpu in @(Get-CimInstance Win32_VideoController)) { [void]$report.Add("GPU: $($gpu.Name); driver=$($gpu.DriverVersion)") }
        foreach ($cpu in @(Get-CimInstance Win32_Processor)) { [void]$report.Add("CPU: $($cpu.Name)") }
        [void]$report.Add("RAM bytes: $((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory)")
    } catch { [void]$report.Add('Hardware info: ' + $_.Exception.Message) }
    $profile = Get-ProfileDir
    $modelDirectory = Join-Path $profile ('qwen3-tts/' + $ModelRevision)
    [void]$report.Add("Model directory: $modelDirectory")
    if (Test-Path -LiteralPath $modelDirectory) {
        foreach ($file in @(Get-ChildItem -LiteralPath $modelDirectory -Filter '*.gguf' -File)) {
            Write-Info2 (T "Проверка SHA256 модели: $($file.Name)" "Checking model SHA256: $($file.Name)")
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $matched = @($ModelSpecs.Keys | Where-Object { $ModelSpecs[$_].Hash -eq $hash -and $ModelSpecs[$_].Bytes -eq $file.Length })
            $status = if ($matched.Count) { 'verified ' + ($matched -join ',') } else { 'UNKNOWN OR CORRUPT' }
            [void]$report.Add("MODEL $($file.Name); bytes=$($file.Length); SHA256=$hash; $status")
            if ($file.Name -eq $ModelSpecs.q8.Name) {
                [void]$report.Add("ACTIVE TALKER: $status (identified by contents; the active filename stays Q8 even for Q4)")
            }
        }
    } else { [void]$report.Add('Model cache is missing.') }
    $runtime = Join-Path $game ($GameName + '_Data/StreamingAssets/kolkata-qwen-runtime')
    try {
        $manifest = Get-Content -LiteralPath (Join-Path $runtime 'runtime-manifest.json') -Raw | ConvertFrom-Json
        [void]$report.Add("Qwen runtime: $($manifest.commit)")
        $runtimeRoot = [IO.Path]::GetFullPath($runtime).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        foreach ($entry in $manifest.files) {
            $file = [IO.Path]::GetFullPath((Join-Path $runtime $entry.path))
            if (-not $file.StartsWith($runtimeRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Runtime manifest path is outside its directory.' }
            $hash = if (Test-Path -LiteralPath $file) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash } else { 'MISSING' }
            $knownWorker = $entry.path -eq 'QwenTtsWorker.exe' -and $hash -in (@($RuntimeSpec.PatchedWorker) + @($RuntimeSpec.PreviousWorkers))
            [void]$report.Add("RUNTIME $($entry.path); upstreamMatch=$($hash -eq $entry.sha256); knownLocalWorker=$knownWorker; SHA256=$hash")
        }
    } catch { [void]$report.Add('Runtime check: ' + $_.Exception.Message) }
    [void]$report.Add('Vulkan0 is the worker backend; the Unity renderer device does not prove the worker device.')
    [void]$report.Add('The patched worker writes Qwen/GGML callbacks to its own log. Some direct native stderr output is still absent from these logs.')
    [IO.File]::WriteAllLines((Join-Path $directory 'system-and-dll.txt'), $report, (New-Object Text.UTF8Encoding $true))
}
function Write-SpeechSummary([string]$directory) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $selected = New-Object 'System.Collections.Generic.List[string]'
    [void]$lines.Add('CURRENT CAPTURE ONLY: Player.log. See the full file for context.')
    [void]$lines.Add('first_audio and succeeded=True do not prove audible or good-quality speech.')
    $source = Join-Path $directory 'log-source.txt'
    if (Test-Path -LiteralPath $source) { [void]$lines.Add([IO.File]::ReadAllText($source)) }
    $current = Join-Path $directory 'Player.log'
    if (Test-Path -LiteralPath $current) {
        $lineNumber = 0; $firstAudio = 0; $succeeded = 0; $cancelled = 0; $failed = 0
        foreach ($line in Get-Content -LiteralPath $current -Encoding UTF8) {
            $lineNumber++
            if ($line -match '\[SpeechRequest\].*provider=qwen\b') {
                if ($line -match '\bstage=first_audio\b') { $firstAudio++ }
                if ($line -match '\bstage=completed\b') {
                    if ($line -match '\bcancelled=True\b') { $cancelled++ }
                    elseif ($line -match '\bsucceeded=True\b') { $succeeded++ }
                    elseif ($line -match '\bsucceeded=False\b') { $failed++ }
                }
            }
            if ($line -match '\[Startup\]|\[SpeechRequest\]|\[Speech\]|\[Qwen|\b\w*Exception\b(?!\s*=\s*none\b)|No audio progress|Slow non-English|\[Shutdown\]') {
                [void]$selected.Add("${lineNumber}: $line")
            }
        }
        [void]$lines.Add("Qwen requests: succeeded=$succeeded; cancelled=$cancelled; failed=$failed; first_audio=$firstAudio")
        [void]$lines.Add("`nFILE: Player.log")
        $lines.AddRange($selected)
    } else {
        [void]$lines.Add('Player.log is missing. No current-run result is available; historical logs are not substituted.')
    }
    $history = @(Get-ChildItem -LiteralPath $directory -Filter '*Player*.log' -File | Where-Object { $_.Name -ne 'Player.log' } | Sort-Object Name)
    if ($history.Count) {
        [void]$lines.Add("`nHISTORICAL / STANDARD-PATH SNAPSHOTS (excluded from the summary):")
        foreach ($file in $history) { [void]$lines.Add($file.Name) }
        [void]$lines.Add('before-/after- files can be identical old logs: a -logFile launch writes to its own Player.log.')
    }
    $workerDirectory = Join-Path $directory 'qwen-worker'
    if (Test-Path -LiteralPath $workerDirectory) {
        [void]$lines.Add("`nCURRENT QWEN WORKER:")
        foreach ($workerLog in @(Get-ChildItem -LiteralPath $workerDirectory -Filter '*.log' -File)) {
            [void]$lines.Add("FILE: qwen-worker/$($workerLog.Name)")
            foreach ($line in Get-Content -LiteralPath $workerLog.FullName -Encoding UTF8) {
                if ($line -match 'WORKER |LOAD |PROFILE |INIT |backend:|FIRST_AUDIO|COMPLETE|ERROR|NONFINITE|CAPTURE|WORKER_EXIT') { [void]$lines.Add($line) }
            }
        }
    }
    [IO.File]::WriteAllLines((Join-Path $directory 'speech-summary.txt'), $lines, (New-Object Text.UTF8Encoding $true))
}
function Complete-Diagnostics([string]$directory) {
    Write-SpeechSummary $directory
    if ($script:SessionLog -and (Test-Path -LiteralPath $script:SessionLog)) {
        try { Copy-Item -LiteralPath $script:SessionLog -Destination (Join-Path $directory 'patcher-session.log') }
        catch { Write-Warn2 (T 'Журнал не скопирован в ZIP; он сохранён рядом, в logs/.' 'Current transcript could not be copied; it is kept in logs/ beside this folder.') }
    }
    $archive = $directory + '.zip'
    Compress-Archive -LiteralPath $directory -DestinationPath $archive
    Write-Ok (T "Архив логов: $archive" "Diagnostic ZIP: $archive")
    Write-Host (T 'Архив сохранён на компьютере. Его можно прислать после проверки.' 'Files stay on this computer. Send this ZIP after testing.')
}
function Copy-RecentWorkerLogs([string]$directory) {
    $source = Join-Path (Get-ProfileDir) 'swyf-qwen-logs'
    if (-not (Test-Path -LiteralPath $source)) { return }
    $target = Join-Path $directory 'previous-qwen-worker'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($file in @(Get-ChildItem -LiteralPath $source -Filter 'qwen-*.log' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 3)) {
        try { Copy-Item -LiteralPath $file.FullName -Destination $target }
        catch { Write-Warn2 $_.Exception.Message }
    }
}
function Save-Diagnostics([string]$game) {
    $directory = New-DiagnosticFolder 'diagnostics'
    [IO.File]::WriteAllText((Join-Path $directory 'log-source.txt'), 'Collected from the standard Unity profile. This can be an older normal launch. Tests started through the patcher have their own logs/test-*/Player.log and ZIP.')
    Copy-PlayerLogs $directory ''
    Copy-RecentWorkerLogs $directory
    Write-DiagnosticReport $game $directory
    Complete-Diagnostics $directory
}
function Invoke-TestLaunch([string]$game) {
    Assert-GameClosed
    $exe = Join-Path $game ($GameName + '.exe')
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Game executable not found.' }
    $directory = New-DiagnosticFolder 'test'
    [IO.File]::WriteAllText((Join-Path $directory 'log-source.txt'), 'This test writes directly to Player.log through -logFile. before-/after- snapshots are from the separate standard Unity profile and may be stale.')
    Copy-PlayerLogs $directory 'before-'
    Write-DiagnosticReport $game $directory
    $log = Join-Path $directory 'Player.log'
    $oldWorkerLog = [Environment]::GetEnvironmentVariable('SWYF_QWEN_LOG_DIR')
    $oldCapture = [Environment]::GetEnvironmentVariable('SWYF_QWEN_CAPTURE')
    try {
        Assert-GameClosed
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_LOG_DIR', (Join-Path $directory 'qwen-worker'))
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_CAPTURE', '1')
        $gameProcess = Start-Process -FilePath $exe -WorkingDirectory $game -ArgumentList @('-logFile', ('"' + $log + '"')) -PassThru
        Write-Info2 (T "Игра запущена, PID=$($gameProcess.Id). Текущий лог: $log" "Game PID=$($gameProcess.Id). Live log: $log")
        Write-Host (T 'Если речь оборвётся, подождите 60 секунд после её начала, затем закройте игру.' 'If speech cuts off, wait 60 seconds after it starts, then close the game.')
        Write-Host (T 'Оставьте это окно открытым: после выхода из игры появится ZIP с логами.' 'Keep this window open. A log ZIP will be created when the game exits.')
        Write-Host (T 'В архив попадёт озвучка первых шести реплик (WAV) для проверки искажений.' 'The archive will include the first six generated replies (WAV) for audio diagnosis.')
        $gameProcess.WaitForExit()
        [IO.File]::WriteAllText((Join-Path $directory 'exit.txt'), "Game exit code: $($gameProcess.ExitCode); time=$(Get-Date -Format o)")
    } finally {
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_LOG_DIR', $oldWorkerLog)
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_CAPTURE', $oldCapture)
        Copy-PlayerLogs $directory 'after-'
        Complete-Diagnostics $directory
    }
}
