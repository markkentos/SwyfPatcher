# Exact runtime shipped with the supplied game; do not mix native ABIs.
$RuntimeSpec = @{
    OriginalWorker = '3BB21D00C77547E9B728B443E7C6ED53F9401694F8A7DEE5A5820F8245B7F333'
    PatchedWorker = '25F2FD20B795A60E360FD4D61537D458F3432663EFEA59B91F9E867908B21B8E'
    OriginalManifest = 'AD40CF8C422E5D3C5E312DB577D3D095969CEB9F9857CA036A947262A810FD85'
    # Previously distributed local worker; upgrades still require its original backup.
    PreviousWorkers = @('3F5236375D4BCB5E90BCC4E4DA51984E7A5BC147A88FF48CABE198A92B735AFB', '053E44B2A12254165454F57FCF19ED19B452036E0EC1F4EE7DF0FE5FC3E37344', '76012AC064DDAD9409EFEB939094DCBCBEAA81AABAB0E8FCB19BA594AB311A22')
    Dependencies = @{
        'qwen3.dll' = '65D6F33A2636856D344B95C7F3186C735CCB25A277431DADAB7BD0DC1BEB7D35'
        'ggml.dll' = 'B6CCEA5B63306D336A764499D3B04A44F4987874F3B54847D9214B9375420E50'
        'ggml-base.dll' = 'CB2C472FF6F2413A5100595B06392382282220AB151F7496C1C006331DFACBD6'
        'gpu/ggml-vulkan.dll' = 'BBFC89AA988AF0370C365F2229FF9228EC599EF31837AF61AB95CCBCA996D91D'
    }
}
function Get-RuntimeDir([string]$game) { return Join-Path $game ($GameName + '_Data/StreamingAssets/kolkata-qwen-runtime') }
function Get-RuntimeManifestPlan([string]$directory, [string]$workerHash) {
    $path = Join-Path $directory 'runtime-manifest.json'
    $current = [IO.File]::ReadAllBytes($path)
    $text = (New-Object Text.UTF8Encoding $false, $true).GetString($current)
    $matches = [regex]::Matches($text, '"path"\s*:\s*"QwenTtsWorker\.exe"\s*,\s*"sha256"\s*:\s*"(?<hash>[a-fA-F0-9]{64})"')
    if ($matches.Count -ne 1) { throw (T 'Неизвестный формат манифеста Qwen. Изменений нет.' 'Unknown Qwen manifest format. No changes made.') }
    $field = $matches[0].Groups['hash']
    $knownWorkers = @($RuntimeSpec.OriginalWorker, $RuntimeSpec.PatchedWorker) + @($RuntimeSpec.PreviousWorkers)
    if ($field.Value -notin $knownWorkers) { throw (T 'Манифест ссылается на неизвестный Qwen-воркер. Изменений нет.' 'Manifest references an unknown Qwen worker. No changes made.') }
    $prefix = $text.Substring(0, $field.Index)
    $suffix = $text.Substring($field.Index + $field.Length)
    $original = [Text.Encoding]::UTF8.GetBytes($prefix + $RuntimeSpec.OriginalWorker.ToLowerInvariant() + $suffix)
    # Reconstruct and verify the complete original: only our worker's hash may differ.
    # This also rejects changed paths, duplicate entries and unrelated manifest edits.
    if ((Sha256Hex $original) -ne $RuntimeSpec.OriginalManifest) {
        throw (T 'Манифест Qwen отличается от поддерживаемого оригинала. Изменений нет.' 'Qwen manifest differs from the supported original. No changes made.')
    }
    $backup = $path + '.swyf.original'
    if ((Test-Path -LiteralPath $backup) -and (Get-FileHash -LiteralPath $backup).Hash -ne $RuntimeSpec.OriginalManifest) {
        throw (T 'Резервная копия манифеста Qwen повреждена или неизвестна.' 'Qwen manifest backup is corrupt or unknown.')
    }
    $output = [Text.Encoding]::UTF8.GetBytes($prefix + $workerHash.ToLowerInvariant() + $suffix)
    return [pscustomobject]@{ Path = $path; Current = $current; CurHash = (Sha256Hex $current); Output = $output; Hash = (Sha256Hex $output); Backup = $backup; Original = $original; WorkerHash = $field.Value.ToUpperInvariant() }
}
function Get-RuntimePlan([string]$game, [bool]$restore = $false) {
    $directory = Get-RuntimeDir $game
    $path = Join-Path $directory 'QwenTtsWorker.exe'
    if (-not (Test-Path -LiteralPath $path)) { throw (T 'QwenTtsWorker.exe не найден. Изменений нет.' 'QwenTtsWorker.exe is missing. No changes made.') }
    $current = [IO.File]::ReadAllBytes($path); $hash = Sha256Hex $current
    $knownWorkers = @($RuntimeSpec.OriginalWorker, $RuntimeSpec.PatchedWorker) + @($RuntimeSpec.PreviousWorkers)
    if ($hash -notin $knownWorkers) {
        throw (T "Неизвестный Qwen-воркер: $hash. Изменений нет." "Unknown Qwen worker: $hash. No changes made.")
    }
    $backup = $path + '.swyf.original'
    if ((Test-Path -LiteralPath $backup) -and (Get-FileHash -LiteralPath $backup).Hash -ne $RuntimeSpec.OriginalWorker) {
        throw (T 'Резервная копия Qwen-воркера отличается от оригинала. Существующий файл сохранён.' 'Qwen worker backup is not the expected original. Existing file preserved.')
    }
    if ($hash -eq $RuntimeSpec.OriginalWorker) { $original = $current }
    else {
        if (-not (Test-Path -LiteralPath $backup)) { throw (T 'Отсутствует оригинальный бэкап Qwen-воркера.' 'Original Qwen worker backup is missing.') }
        $original = [IO.File]::ReadAllBytes($backup)
    }
    if ($restore) { $next = $original; $target = $RuntimeSpec.OriginalWorker }
    else {
        foreach ($name in $RuntimeSpec.Dependencies.Keys) {
            $dependency = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $dependency) -or (Get-FileHash -LiteralPath $dependency).Hash -ne $RuntimeSpec.Dependencies[$name]) {
                throw (T "Несовместимый Qwen runtime: $name. Изменений нет." "Incompatible Qwen runtime: $name. No changes made.")
            }
        }
        $next = [IO.File]::ReadAllBytes((Join-Path $PatcherRoot 'payload/QwenTtsWorker.exe'))
        $target = $RuntimeSpec.PatchedWorker
    }
    if ((Sha256Hex $original) -ne $RuntimeSpec.OriginalWorker -or (Sha256Hex $next) -ne $target) {
        throw (T 'Хеш Qwen-воркера не совпадает. Изменений нет.' 'Qwen worker hash mismatch. No changes made.')
    }
    $manifest = Get-RuntimeManifestPlan $directory $target
    if (-not $restore) {
        $document = [Text.Encoding]::UTF8.GetString($manifest.Original) | ConvertFrom-Json
        foreach ($entry in $document.files) {
            if ($entry.path -eq 'QwenTtsWorker.exe') { continue }
            $file = Join-Path $directory $entry.path
            if (-not (Test-Path -LiteralPath $file) -or (Get-FileHash -LiteralPath $file).Hash -ne $entry.sha256) {
                throw (T "Контрольная сумма Qwen runtime не совпадает: $($entry.path). Изменений нет." "Qwen runtime checksum mismatch: $($entry.path). No changes made.")
            }
        }
    }
    return [pscustomobject]@{ Path = $path; Current = $current; CurHash = $hash; Output = $next; Hash = $target; Backup = $backup; Original = $original; Restore = $restore; Manifest = $manifest }
}
function Save-RuntimeBackup([string]$path, [byte[]]$bytes, [string]$hash) {
    if (-not (Test-Path -LiteralPath $path)) {
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $path).Hash -ne $hash) { throw 'Runtime backup verification failed: ' + $path }
}
function Undo-RuntimePlan($plan) {
    # Restore only files still containing our exact output. Preserve concurrent writes.
    foreach ($item in @($plan.Manifest, $plan)) {
        if ($item.CurHash -eq $item.Hash) { continue }
        try {
            if ((Get-FileHash -LiteralPath $item.Path).Hash -eq $item.Hash) {
                ReplaceVerified $item.Path $item.Output $item.Current $item.CurHash
            }
        } catch { Write-Warn2 ((T 'Не удалось откатить runtime: ' 'Runtime rollback failed: ') + $_.Exception.Message) }
    }
}
function Set-RuntimePlan($plan) {
    Assert-GameClosed
    foreach ($item in @($plan, $plan.Manifest)) {
        if ((Get-FileHash -LiteralPath $item.Path).Hash -ne $item.CurHash) { throw 'Runtime changed after validation: ' + $item.Path }
    }
    if (-not $plan.Restore) {
        Save-RuntimeBackup $plan.Backup $plan.Original $RuntimeSpec.OriginalWorker
        Save-RuntimeBackup $plan.Manifest.Backup $plan.Manifest.Original $RuntimeSpec.OriginalManifest
    }
    try {
        if ($plan.CurHash -ne $plan.Hash) { ReplaceVerified $plan.Path $plan.Current $plan.Output $plan.Hash }
        if ($plan.Manifest.CurHash -ne $plan.Manifest.Hash) {
            ReplaceVerified $plan.Manifest.Path $plan.Manifest.Current $plan.Manifest.Output $plan.Manifest.Hash
        }
        foreach ($item in @($plan, $plan.Manifest)) {
            if ((Get-FileHash -LiteralPath $item.Path).Hash -ne $item.Hash) { throw 'Runtime post-install verification failed: ' + $item.Path }
        }
    } catch { $failure = $_; Undo-RuntimePlan $plan; throw $failure }
    if ($plan.Restore) { Write-Ok (T 'Оригинальные Qwen-воркер и манифест восстановлены.' 'Original Qwen worker and manifest restored.'); return }
    Write-Ok (T 'Qwen-воркер и манифест согласованы; контрольная сумма проверена.' 'Qwen worker and manifest synchronized; checksum verified.')
}
function Write-RuntimeStatus([string]$game) {
    try {
        $plan = Get-RuntimePlan $game
        $status = if ($plan.CurHash -eq $RuntimeSpec.PatchedWorker) { T 'установлен' 'installed' } else { T 'нужно обновить' 'update needed' }
        Write-Host (T "Qwen-воркер: $status" "Qwen worker: $status")
        if ($plan.Manifest.WorkerHash -ne $plan.CurHash) {
            Write-Warn2 (T 'Контрольная сумма в манифесте НЕ совпадает с воркером: игра отключит Qwen. Выберите 2 для исправления.' 'Manifest checksum does NOT match the worker: the game will disable Qwen. Choose 2 to repair.')
        } else { Write-Ok (T 'Контрольная сумма воркера совпадает с манифестом.' 'Worker checksum matches the manifest.') }
    } catch { Write-Warn2 $_.Exception.Message }
    try {
        $file = Join-Path (Get-QwenModelDir) $ModelSpecs.q8.Name
        $hash = (Get-FileHash -LiteralPath $file).Hash
        $kind = @('q4', 'q8') | Where-Object { $ModelSpecs[$_].Hash -eq $hash }
        if (-not $kind) { $kind = T 'неизвестная' 'unknown' }
        Write-Host (T "Активная модель по SHA256: $kind ($hash)" "Active model by SHA256: $kind ($hash)")
    } catch { Write-Warn2 (T 'Модель пока недоступна для проверки SHA256.' 'Model is not available for SHA256 verification yet.') }
}
function Assert-RuntimeManifestReady([string]$game) {
    $directory = Get-RuntimeDir $game
    $hash = (Get-FileHash -LiteralPath (Join-Path $directory 'QwenTtsWorker.exe')).Hash
    $manifest = Get-RuntimeManifestPlan $directory $hash
    if ($manifest.WorkerHash -ne $hash) {
        throw (T 'Запуск отменён: манифест не соответствует Qwen-воркеру. Выберите 2 — применить / обновить патч, затем 7.' 'Launch cancelled: the manifest does not match the Qwen worker. Choose 2 — Apply / update patch, then 7.')
    }
}
