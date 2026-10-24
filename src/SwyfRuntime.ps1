# Exact runtime shipped with the supplied game; do not mix native ABIs.
$RuntimeSpec = @{
    OriginalWorker = '3BB21D00C77547E9B728B443E7C6ED53F9401694F8A7DEE5A5820F8245B7F333'
    PatchedWorker = '053E44B2A12254165454F57FCF19ED19B452036E0EC1F4EE7DF0FE5FC3E37344'
    # Previously distributed local worker; upgrades still require its original backup.
    PreviousWorkers = @('76012AC064DDAD9409EFEB939094DCBCBEAA81AABAB0E8FCB19BA594AB311A22')
    Dependencies = @{
        'qwen3.dll' = '65D6F33A2636856D344B95C7F3186C735CCB25A277431DADAB7BD0DC1BEB7D35'
        'ggml.dll' = 'B6CCEA5B63306D336A764499D3B04A44F4987874F3B54847D9214B9375420E50'
        'ggml-base.dll' = 'CB2C472FF6F2413A5100595B06392382282220AB151F7496C1C006331DFACBD6'
        'gpu/ggml-vulkan.dll' = 'BBFC89AA988AF0370C365F2229FF9228EC599EF31837AF61AB95CCBCA996D91D'
    }
}
function Get-RuntimeDir([string]$game) { return Join-Path $game ($GameName + '_Data/StreamingAssets/kolkata-qwen-runtime') }
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
    if ($restore) {
        if ($hash -eq $RuntimeSpec.OriginalWorker) { $next = $current }
        else {
            if (-not (Test-Path -LiteralPath $backup)) { throw (T 'Нет резервной копии Qwen-воркера.' 'Qwen worker backup is missing.') }
            $next = [IO.File]::ReadAllBytes($backup)
        }
        $target = $RuntimeSpec.OriginalWorker
    } else {
        foreach ($name in $RuntimeSpec.Dependencies.Keys) {
            $dependency = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $dependency) -or (Get-FileHash -LiteralPath $dependency).Hash -ne $RuntimeSpec.Dependencies[$name]) {
                throw (T "Несовместимый Qwen runtime: $name. Изменений нет." "Incompatible Qwen runtime: $name. No changes made.")
            }
        }
        $next = [IO.File]::ReadAllBytes((Join-Path $PatcherRoot 'payload/QwenTtsWorker.exe'))
        $target = $RuntimeSpec.PatchedWorker
        if ((Test-Path -LiteralPath $backup) -and (Get-FileHash -LiteralPath $backup).Hash -ne $RuntimeSpec.OriginalWorker) {
            throw (T 'Резервная копия Qwen-воркера отличается от оригинала. Существующий файл сохранён.' 'Qwen worker backup is not the expected original. Existing file preserved.')
        }
        if ($hash -ne $RuntimeSpec.OriginalWorker -and -not (Test-Path -LiteralPath $backup)) {
            throw (T 'Отсутствует оригинальный бэкап Qwen-воркера.' 'Original Qwen worker backup is missing.')
        }
    }
    if ((Sha256Hex $next) -ne $target) { throw (T 'Хеш Qwen-воркера не совпадает. Изменений нет.' 'Qwen worker hash mismatch. No changes made.') }
    return [pscustomobject]@{ Path = $path; Current = $current; CurHash = $hash; Output = $next; Hash = $target; Backup = $backup; Restore = $restore }
}
function Set-RuntimePlan($plan) {
    Assert-GameClosed
    if ($plan.CurHash -eq $plan.Hash) { return }
    if (-not $plan.Restore -and -not (Test-Path -LiteralPath $plan.Backup)) {
        # CreateNew prevents overwriting a backup created by another process.
        $stream = [IO.File]::Open($plan.Backup, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($plan.Current, 0, $plan.Current.Length) } finally { $stream.Dispose() }
        if ((Get-FileHash -LiteralPath $plan.Backup).Hash -ne $RuntimeSpec.OriginalWorker) { throw 'Qwen worker backup verification failed.' }
    }
    ReplaceVerified $plan.Path $plan.Current $plan.Output $plan.Hash
    if ($plan.Restore) { Write-Ok (T 'Оригинальный Qwen-воркер восстановлен.' 'Original Qwen worker restored.'); return }
    Write-Ok (T 'Qwen-воркер обновлён: совместимый режим Q4/Vulkan и журнал синтеза.' 'Qwen worker updated: Q4/Vulkan compatibility path and synthesis logging.')
}
function Write-RuntimeStatus([string]$game) {
    try {
        $plan = Get-RuntimePlan $game
        $status = if ($plan.CurHash -eq $RuntimeSpec.PatchedWorker) { T 'установлено' 'installed' } else { T 'требуется установка' 'not installed' }
        Write-Host (T "Исправление Q4/Vulkan: $status" "Q4/Vulkan compatibility: $status")
    } catch { Write-Warn2 $_.Exception.Message }
    try {
        $file = Join-Path (Get-QwenModelDir) $ModelSpecs.q8.Name
        $hash = (Get-FileHash -LiteralPath $file).Hash
        $kind = @('q4', 'q8') | Where-Object { $ModelSpecs[$_].Hash -eq $hash }
        if (-not $kind) { $kind = T 'неизвестная' 'unknown' }
        Write-Host (T "Активная модель по SHA256: $kind ($hash)" "Active model by SHA256: $kind ($hash)")
    } catch { Write-Warn2 (T 'Модель пока недоступна для проверки SHA256.' 'Model is not available for SHA256 verification yet.') }
}
