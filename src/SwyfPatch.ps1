# SwyfPatcher: exact-hash Unity/Mono patching and local diagnostic collection.
# Original hardware/timeout fix: psihozniy. Original PowerShell patcher: markkentos.
# Local 2.9 repair: valid VerifyAsync branch, original voice reference, safe menu and logs.
# Dot-sourcing loads functions for tests; only direct execution enters the UI.
$ErrorActionPreference = 'Stop'
$Version = '2.9.7'
$GameName = 'Scam With Your Friends'
$PatcherRoot = Split-Path -Parent $PSScriptRoot
$SessionLog = $null
. (Join-Path $PSScriptRoot 'SwyfLanguage.ps1')
. (Join-Path $PSScriptRoot 'PatchTables.ps1')

function HexToBytes([string]$s) {
    if ($s.Length % 2) { throw 'Odd-length patch bytes.' }
    $bytes = New-Object byte[] ($s.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($s.Substring($i * 2, 2), 16) }
    return ,$bytes
}
function Sha256Hex([byte[]]$bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}
function MatchesAt([byte[]]$data, [int]$offset, [byte[]]$expected) {
    if ($offset -lt 0 -or $offset + $expected.Length -gt $data.Length) { return $false }
    for ($i = 0; $i -lt $expected.Length; $i++) { if ($data[$offset + $i] -ne $expected[$i]) { return $false } }
    return $true
}
function CopyInto([byte[]]$data, [int]$offset, [byte[]]$bytes) {
    if ($offset -lt 0 -or $offset + $bytes.Length -gt $data.Length) { throw 'Patch outside file bounds.' }
    [Array]::Copy($bytes, 0, $data, $offset, $bytes.Length)
}
function Write-Ok([string]$message) { Write-Host "[OK] $message" -ForegroundColor Green }
function Write-Info2([string]$message) { Write-Host "[INFO] $message" -ForegroundColor Cyan }
function Write-Warn2([string]$message) { Write-Host "[WARN] $message" -ForegroundColor Yellow }

function ReplaceVerified([string]$path, [byte[]]$current, [byte[]]$next, [string]$expectedHash) {
    $temporary = "$path.swyf-$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        if ((Sha256Hex $next) -ne $expectedHash) { throw 'Output hash mismatch. No replacement.' }
        [IO.File]::WriteAllBytes($temporary, $next)
        if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Temporary file hash mismatch.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne (Sha256Hex $current)) { throw 'File changed during operation. No replacement.' }
        [IO.File]::Replace($temporary, $path, [NullString]::Value)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Final file hash mismatch.' }
}

function Convert-Options([string[]]$Arguments) {
    $options = @{ Backend = ''; Model = ''; Reference = 0; GamePath = ''; Lang = ''; Action = 'patch'; Cli = $false }
    $seen = @{}
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        if ($arg.StartsWith('-')) {
            $key = $arg.TrimStart('-').ToLowerInvariant()
            if ($key -eq 'referenceseconds') { $key = 'reference' }
            if ($key -eq 'diagnostics') { $key = 'logs' }
            if ($seen.ContainsKey($key)) { throw "Duplicate option: $arg" }
            $seen[$key] = $true
            if ($key -in @('backend', 'model', 'reference', 'gamepath', 'lang')) {
                if (++$i -ge $Arguments.Count -or $Arguments[$i].StartsWith('-')) { throw "Missing value for $arg" }
                $value = $Arguments[$i]
                switch ($key) {
                    'lang' { $options.Lang = $value.ToLowerInvariant() }
                    'backend' { $options.Backend = $value.ToLowerInvariant() }
                    'model' { $options.Model = $value.ToLowerInvariant() }
                    'reference' {
                        if ($value -notin @('3', '10')) { throw 'Reference must be 3 or 10 seconds.' }
                        $options.Reference = [int]$value
                    }
                    'gamepath' {
                        if ($options.GamePath) { throw 'Specify one game folder.' }
                        $options.GamePath = $value
                    }
                }
                if ($key -notin @('gamepath', 'lang')) { $options.Cli = $true }
            } elseif ($key -in @('check', 'restore', 'launch', 'logs')) {
                if ($options.Action -ne 'patch') { throw 'Choose only one of --check, --restore, --launch, --logs.' }
                $options.Action = $key; $options.Cli = $true
            } elseif ($key -eq 'noninteractive') { $options.Cli = $true }
            elseif ($key -in @('help', 'h', '?')) { $options.Action = 'help'; $options.Cli = $true }
            else { throw "Unknown option: $arg" }
        } else {
            if ($options.GamePath) { throw 'Specify one game folder.' }
            $options.GamePath = $arg
        }
    }
    if ($options.Lang -and $options.Lang -notin @('ru', 'en')) { throw 'Language must be ru or en.' }
    if ($options.Backend -and $options.Backend -notin @('auto', 'cpu', 'vulkan')) { throw 'Backend must be auto, cpu or vulkan.' }
    if ($options.Model -and $options.Model -notin @('q4', 'q8')) { throw 'Model must be q4 or q8.' }
    if ($options.Action -in @('restore', 'launch', 'logs') -and ($options.Backend -or $options.Model -or $options.Reference)) {
        throw 'Restore/launch/logs cannot be combined with patch or model options.'
    }
    return [pscustomobject]$options
}

function Find-Game([string]$explicitPath) {
    if ($explicitPath) {
        $resolved = (Resolve-Path -LiteralPath $explicitPath).Path
        if (-not (Test-Path -LiteralPath (Join-Path $resolved ($GameName + '_Data/Managed/Assembly-CSharp.dll')))) { throw 'Select the game root folder containing the EXE and _Data directory.' }
        return $resolved
    }
    # A patcher placed in/next to this installation takes precedence over Steam discovery.
    foreach ($candidate in @($PatcherRoot, (Split-Path -Parent $PatcherRoot), (Get-Location).Path)) {
        if (Test-Path -LiteralPath (Join-Path $candidate ($GameName + '_Data/Managed/Assembly-CSharp.dll'))) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $libraries = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $roots = @()
    if (Test-Path 'HKCU:/Software/Valve/Steam') {
        $steam = (Get-ItemProperty 'HKCU:/Software/Valve/Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steam) { $roots += $steam }
    }
    if (Test-Path 'C:/Program Files (x86)/Steam') { $roots += 'C:/Program Files (x86)/Steam' }
    foreach ($root in $roots) {
        [void]$libraries.Add((Join-Path $root 'steamapps/common'))
        $vdf = Join-Path $root 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $library = $match.Groups[1].Value.Replace('\\', '\')
                [void]$libraries.Add((Join-Path $library 'steamapps/common'))
            }
        }
    }
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if (-not $drive.IsReady) { continue }
        foreach ($relative in @('SteamLibrary/steamapps/common', 'Steam/steamapps/common', 'Program Files (x86)/Steam/steamapps/common')) {
            [void]$libraries.Add((Join-Path $drive.RootDirectory.FullName $relative))
        }
    }
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        $candidate = Join-Path $library $GameName
        if (Test-Path -LiteralPath (Join-Path $candidate ($GameName + '_Data/Managed/Assembly-CSharp.dll'))) { [void]$found.Add((Resolve-Path -LiteralPath $candidate).Path) }
    }
    if ($found.Count -ne 1) { throw ("Found $($found.Count) game folders. Drag the correct game folder onto SwyfPatch.bat.`n" + ($found -join "`n")) }
    return @($found)[0]
}

function Get-Context([string]$game) {
    $managed = Join-Path $game ($GameName + '_Data/Managed')
    $dll = Join-Path $managed 'Assembly-CSharp.dll'
    $current = [IO.File]::ReadAllBytes($dll); $hash = Sha256Hex $current
    $build = $null; $variant = ''; $reference = 0; $legacy = $false
    foreach ($item in $Builds) {
        if ($hash -eq $item.Original) { $build = $item; break }
        foreach ($backend in @('auto', 'cpu', 'vulkan')) {
            if ($item.Patched[$backend] -eq $hash) { $build = $item; $variant = $backend; $reference = $item.DefaultReference; break }
            if ($item.Patched3 -and $item.Patched3[$backend] -eq $hash) { $build = $item; $variant = $backend; $reference = 3; break }
        }
        if ($build) { break }
        foreach ($previous in $item.PreviousPatches) {
            if ($previous.Hash -eq $hash) {
                $build = $item; $variant = $previous.Backend; $reference = $previous.Reference; break
            }
        }
        if ($build) { break }
        if ($LegacyPatched.ContainsKey($item.Original) -and $LegacyPatched[$item.Original].ContainsKey($hash)) {
            $build = $item; $variant = $LegacyPatched[$item.Original][$hash]; $reference = 3; $legacy = $true; break
        }
    }
    if (-not $build) { throw "Unsupported Assembly-CSharp.dll SHA256: $hash. No changes made. Save diagnostics with --logs." }
    foreach ($dependency in @(@{ Name = 'ScriptsAssDef.dll'; Hash = $build.Scripts }, @{ Name = 'Kolkata.Speech.dll'; Hash = $build.Speech })) {
        if (-not $dependency.Hash) { continue }
        $path = Join-Path $managed $dependency.Name
        if (-not (Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $dependency.Hash) { throw "Wrong or missing $($dependency.Name). No changes made." }
    }
    return [pscustomobject]@{ Game = $game; Dll = $dll; Current = $current; CurHash = $hash; Build = $build; Already = [bool]$variant; CurVariant = $variant; ReferenceSeconds = $reference; Legacy = $legacy }
}

function Get-PatchPlan($ctx, [string]$backend, [int]$reference = 0) {
    if (-not $backend) { $backend = if ($ctx.Already) { $ctx.CurVariant } else { 'auto' } }
    if (-not $reference) { $reference = $ctx.Build.DefaultReference }
    if (-not $ctx.Build.Blocks[$backend]) { throw "Backend $backend is unsupported for build $($ctx.Build.Tag)." }
    if ($reference -eq $ctx.Build.DefaultReference) { $hash = $ctx.Build.Patched[$backend] }
    elseif ($reference -eq 3 -and $ctx.Build.Patched3) { $hash = $ctx.Build.Patched3[$backend] }
    else { throw "Reference $reference is unsupported for build $($ctx.Build.Tag)." }
    $edits = @($ctx.Build.Edits | ForEach-Object {
        $edit = $_.Clone()
        if ($edit.Reference) { $edit.a = '{0:X2}' -f $reference; $edit.d = "Voice reference: $reference seconds" }
        $edit
    }) + @(@{ o = $ctx.Build.HwOffset; b = $ctx.Build.HwBefore; a = $ctx.Build.Blocks[$backend]; d = "Hardware allowed; backend: $backend" })
    $source = [byte[]]$ctx.Current.Clone()
    if ($ctx.Already) { foreach ($edit in $edits) { CopyInto $source $edit.o (HexToBytes $edit.b) } }
    if ((Sha256Hex $source) -ne $ctx.Build.Original) { throw 'Original reconstruction failed. No changes made.' }
    $output = [byte[]]$source.Clone()
    foreach ($edit in $edits) {
        $before = HexToBytes $edit.b; $after = HexToBytes $edit.a
        if ($before.Length -ne $after.Length -or -not (MatchesAt $source $edit.o $before)) { throw "Invalid edit: $($edit.d). No changes made." }
        CopyInto $output $edit.o $after
    }
    if ((Sha256Hex $output) -ne $hash) { throw 'Output hash mismatch. No changes made.' }
    return [pscustomobject]@{ Source = $source; Output = $output; Hash = $hash; Backend = $backend; Reference = $reference; Edits = $edits }
}

function Assert-GameClosed {
    $running = @(Get-Process -Name $GameName, 'QwenTtsWorker' -ErrorAction SilentlyContinue)
    if ($running.Count) { throw ('Close the game and QwenTtsWorker in Task Manager first: ' + (($running | Select-Object -ExpandProperty ProcessName -Unique) -join ', ')) }
}
function Save-OriginalBackup($ctx, [byte[]]$source) {
    $candidates = @('.swyf.original', '.swyf-v23.original', '.swyf-v22.original', ('.swyf.' + $ctx.Build.Original.Substring(0, 12) + '.original'))
    foreach ($suffix in $candidates) {
        $path = $ctx.Dll + $suffix
        if ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $ctx.Build.Original) { return $path }
    }
    $path = $ctx.Dll + '.swyf.original'
    if (Test-Path -LiteralPath $path) { $path = $ctx.Dll + $candidates[-1] }
    if (Test-Path -LiteralPath $path) { throw 'Backup path already contains unrelated data. No DLL replacement.' }
    [IO.File]::WriteAllBytes($path, $source)
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $ctx.Build.Original) { throw 'Backup verification failed.' }
    return $path
}
function Set-VoicePreference {
    $key = 'HKCU:/Software/Jatater Worldwide/' + $GameName
    if (-not (Test-Path -LiteralPath $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -LiteralPath $key -Name 'Kolkata.Qwen3Tts_h1324939569' -PropertyType DWord -Value 0 -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name 'Kolkata.Dev.RussianSpeechProvider_h3030369888' -PropertyType DWord -Value 0 -Force | Out-Null
}
function Invoke-Patch($ctx, [string]$backend, [int]$reference = 0, [string]$model = '') {
    Assert-GameClosed
    $plan = Get-PatchPlan $ctx $backend $reference
    $runtimePlan = Get-RuntimePlan $ctx.Game
    # Verify/download all required models before changing DLLs. Read-only checks never enter here.
    $modelPlan = Prepare-ModelSwitch $model
    try {
        Assert-GameClosed
        $backup = Save-OriginalBackup $ctx $plan.Source
        Write-Info2 (T 'Патч проверен. Применяю изменения...' 'Patch verified. Applying changes...')
        Set-RuntimePlan $runtimePlan
        try {
            if ($ctx.CurHash -ne $plan.Hash) { ReplaceVerified $ctx.Dll $ctx.Current $plan.Output $plan.Hash }
            Complete-ModelSwitch $modelPlan
        } catch {
            # Roll back only our own bytes; never clobber a concurrent change.
            $failure = $_
            if ($ctx.CurHash -ne $plan.Hash -and (Get-FileHash -LiteralPath $ctx.Dll).Hash -eq $plan.Hash) {
                ReplaceVerified $ctx.Dll $plan.Output $ctx.Current $ctx.CurHash
            }
            Undo-RuntimePlan $runtimePlan
            throw $failure
        }
    } finally { Clear-ModelPlan $modelPlan }
    try { Set-VoicePreference } catch { Write-Warn2 ((T 'Выберите Qwen в настройках игры; ошибка реестра: ' 'Select Qwen in game settings; registry update failed: ') + $_.Exception.Message) }
    Write-Ok (T "Готово. Обработка: $($plan.Backend), образец: $($plan.Reference) с; SHA256=$($plan.Hash)" "Patched. Backend=$($plan.Backend), reference=$($plan.Reference)s; SHA256=$($plan.Hash)")
    Write-Host (T "Резервная копия: $backup" "Original backup: $backup")
    try { Install-LogShortcut $ctx.Game } catch { Write-Warn2 ((T 'Ярлык логов не создан: ' 'Log shortcut was not created: ') + $_.Exception.Message) }
    Write-Host (T 'Логи и первые 6 реплик Qwen сохраняются автоматически. Запускайте игру как обычно; после игры пункт 7 соберёт ZIP.' 'Logs and the first 6 Qwen replies are saved automatically. Launch the game normally; use option 7 afterwards to collect a ZIP.')
}
function Invoke-Check($ctx, [string]$backend, [int]$reference = 0, [string]$model = '') {
    $plan = Get-PatchPlan $ctx $backend $reference
    if ($ctx.Already) {
        Write-Host (T "Текущие настройки: обработка=$($ctx.CurVariant), образец=$($ctx.ReferenceSeconds) с, старый патч=$($ctx.Legacy)" "Current settings: backend=$($ctx.CurVariant), reference=$($ctx.ReferenceSeconds)s, legacy patch=$($ctx.Legacy)")
    } else { Write-Host (T 'Текущее состояние: оригинальная DLL.' 'Current status: original DLL.') }
    Write-Ok (T "Сборка $($ctx.Build.Tag); текущая DLL=$($ctx.CurHash)" "Build $($ctx.Build.Tag); current DLL=$($ctx.CurHash)")
    Write-Host (T "При применении: обработка=$($plan.Backend), образец=$($plan.Reference) с, SHA256=$($plan.Hash)" "If applied: backend=$($plan.Backend), reference=$($plan.Reference)s, SHA256=$($plan.Hash)")
    if ($model) { Write-Host (T "Запрошена модель $model (без загрузки и переключения)." "Requested model: $model (not downloaded or switched in check mode).") }
    Write-RuntimeStatus $ctx.Game
    Write-Ok (T 'ТОЛЬКО ПРОВЕРКА. DLL, модели и настройки не изменены.' 'CHECK ONLY. Game DLLs, models and settings were not changed.')
}
function Invoke-Restore($ctx) {
    Assert-GameClosed
    $runtimePlan = Get-RuntimePlan $ctx.Game $true
    if (-not $ctx.Already) { Set-RuntimePlan $runtimePlan; Write-Ok (T 'DLL уже оригинальная.' 'DLL is already original.'); return }
    $plan = Get-PatchPlan $ctx $ctx.CurVariant $ctx.Build.DefaultReference
    $backup = Save-OriginalBackup $ctx $plan.Source
    Set-RuntimePlan $runtimePlan
    try { ReplaceVerified $ctx.Dll $ctx.Current $plan.Source $ctx.Build.Original }
    catch { $failure = $_; Undo-RuntimePlan $runtimePlan; throw $failure }
    Write-Ok (T "Оригинальная DLL восстановлена. Проверенная копия: $backup" "Original DLL restored. Verified backup: $backup")
    Write-Host (T 'Модели и настройки голоса не изменены.' 'Models and voice preferences are unchanged.')
}

. (Join-Path $PSScriptRoot 'SwyfModels.ps1')
. (Join-Path $PSScriptRoot 'SwyfRuntime.ps1')
. (Join-Path $PSScriptRoot 'SwyfDiagnostics.ps1')

function Invoke-Action([string]$game, [string]$action, [string]$backend = '', [int]$reference = 0, [string]$model = '') {
    switch ($action) {
        'launch' { Invoke-TestLaunch $game; return }
        'logs' { Save-Diagnostics $game; return }
        'check' { Invoke-Check (Get-Context $game) $backend $reference $model; return }
        'restore' { Invoke-Restore (Get-Context $game); return }
        'patch' { Invoke-Patch (Get-Context $game) $backend $reference $model; return }
        default { throw "Unknown action: $action" }
    }
}
function Invoke-MenuAction([string]$game, [string]$choice) {
    switch ($choice) {
        '1' { Invoke-Action $game 'check' }
        '2' { Invoke-Action $game 'patch' }
        '3' { Invoke-Action $game 'patch' 'cpu' }
        '4' { Invoke-Action $game 'patch' 'vulkan' }
        '5' { Invoke-Action $game 'patch' '' 0 'q4' }
        '6' { Invoke-Action $game 'patch' '' 0 'q8' }
        '7' { Invoke-Action $game 'logs' }
        '8' { Switch-Language }
        default { throw (T 'Выберите пункт из меню. Изменений нет.' 'Choose a listed action. No changes made.') }
    }
}
function Invoke-Main([string[]]$Arguments) {
    $transcriptStarted = $false
    try {
        $options = Convert-Options $Arguments
        Initialize-Language $options.Lang
        if ($options.Action -eq 'help') {
            Write-Host 'SwyfPatch.bat [game-folder] [--backend auto|cpu|vulkan] [--model q4|q8] [--reference 3|10] [--lang ru|en]'
            Write-Host (T 'Действия: --check (проверка), --restore (откат DLL), --launch (игра + логи), --logs (сбор логов).' 'Actions: --check (dry-run), --restore, --launch (game + logs), --logs (collect only).')
            Write-Host (T 'Без флагов: меню. Путь к папке игры также открывает меню.' 'No options: interactive menu. A folder alone also opens the menu.')
            return 0
        }
        try {
            $logRoot = Join-Path $PatcherRoot 'logs'; New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
            $script:SessionLog = Join-Path $logRoot ('patcher-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
            Start-Transcript -LiteralPath $script:SessionLog -ErrorAction Stop | Out-Null
            $transcriptStarted = $true
        } catch { Write-Warn2 ((T 'Не удалось открыть журнал патчера: ' 'Patcher transcript unavailable: ') + $_.Exception.Message) }
        $game = Find-Game $options.GamePath
        Write-Host "SwyfPatcher $Version"
        Write-Host ((T 'Игра: ' 'Game: ') + $game)
        if ($options.Cli) { Invoke-Action $game $options.Action $options.Backend $options.Reference $options.Model; return 0 }
        while ($true) {
            try {
                $ctx = Get-Context $game
                $state = if ($ctx.Legacy) { T 'нужно обновить' 'update needed' } elseif ($ctx.Already) { T 'установлен' 'installed' } else { T 'не установлен' 'not installed' }
                $backend = if ($ctx.Already) { $ctx.CurVariant } else { T 'штатная' 'original' }
                Write-Host ((T "`nПатч: $state | Обработка: $backend" "`nPatch: $state | Backend: $backend")) -ForegroundColor Yellow
                Write-Host ((T 'Модель: ' 'Model: ') + (Get-ActiveModelKind))
            } catch { Write-Warn2 $_.Exception.Message }
            Show-MainMenu
            $choice = Read-Host (T 'Выбор' 'Choice')
            if ($null -eq $choice -or ($choice -eq '' -and [Console]::IsInputRedirected)) { return 0 }
            $choice = $choice.Trim()
            if ($choice -eq '0') { return 0 }
            if ($choice -eq '') { continue }
            try { Invoke-MenuAction $game $choice } catch { Write-Host ('[FAIL] ' + $_.Exception.Message) -ForegroundColor Red }
        }
    } catch {
        Write-Host ('[FAIL] ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host $_.ScriptStackTrace
        return 1
    } finally {
        if ($transcriptStarted) { Stop-Transcript | Out-Null }
        if ($script:SessionLog) { Write-Host ((T 'Журнал патчера: ' 'Patcher log: ') + $script:SessionLog) }
    }
}
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Main -Arguments $args) }
