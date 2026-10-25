# Immutable model versions match the game's Qwen model table (verified from the DLL).
$ModelRevision = 'b7ee2e8c7459c3bea99da23e3d178125a7d1713c'
$ModelSpecs = @{
    q8 = @{ Name = 'qwen-talker-0.6b-base-Q8_0.gguf'; Bytes = 992615488L; Hash = 'D54DBAF10591421FA764ED630D764EFA717AE40CD959BD48C66D4EB1AF226426' }
    q4 = @{ Name = 'qwen-talker-0.6b-base-Q4_K_M.gguf'; Bytes = 628905056L; Hash = '4B468EC7B1F62B90EF4CA316C0AA57DEADFD54B2CF9651703EA753CEDAF04226' }
    codec = @{ Name = 'qwen-tokenizer-12hz-Q8_0.gguf'; Bytes = 291150624L; Hash = '1883BEEED99348FC35E23DD225E9082F93F6F8C109330A33D935BAA8ACDBFD94' }
}
function Get-ProfileDir {
    return Join-Path $env:USERPROFILE ('AppData/LocalLow/Jatater Worldwide/' + $GameName)
}
function Get-QwenModelDir([switch]$Create) {
    $directory = Join-Path (Get-ProfileDir) ('qwen3-tts/' + $ModelRevision)
    if ($Create) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Model cache not found: $directory. Apply the patch to download verified models." }
    return $directory
}
function Get-ActiveModelKind {
    try {
        $path = Join-Path (Get-QwenModelDir) $ModelSpecs.q8.Name
        if (-not (Test-Path -LiteralPath $path)) { return (T 'файл отсутствует' 'file missing') }
        $length = (Get-Item -LiteralPath $path).Length
        if ($length -eq $ModelSpecs.q8.Bytes) { return (T 'Q8 (по размеру)' 'Q8 (by size)') }
        if ($length -eq $ModelSpecs.q4.Bytes) { return (T 'Q4 (по размеру)' 'Q4 (by size)') }
        return (T "неизвестная / неполная ($length байт)" "unknown / incomplete ($length bytes)")
    } catch { return (T 'не загружена' 'not downloaded') }
}
function Test-ModelFile([string]$path, $spec) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $path).Length -ne $spec.Bytes) { return $false }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $spec.Hash
}
function Assert-ModelFile([string]$path, $spec) {
    if (-not (Test-ModelFile $path $spec)) { throw "Missing or invalid model: $path. Expected SHA256 $($spec.Hash). Active model was not replaced." }
}
function Get-ModelHash([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Expected a model file, found a directory: $path" }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Download-VerifiedModel([string]$destination, $spec) {
    # Downloads only enter a private staging folder, never the live model path.
    if (Test-Path -LiteralPath $destination) { throw "Download staging file already exists: $destination" }
    $temporary = $destination + '.download-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $urls = @(
        "https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)",
        "https://hf-mirror.com/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)",
        "https://hf.aihoster.ru/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)"
    )
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $valid = $false
        foreach ($url in $urls) {
            try {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
                Write-Info2 (T "Загружаю $($spec.Name) ($($spec.Bytes) байт): $url" "Downloading $($spec.Name) ($($spec.Bytes) bytes): $url")
                Invoke-WebRequest -Uri $url -OutFile $temporary -UseBasicParsing -TimeoutSec 1800 | Out-Null
                Assert-ModelFile $temporary $spec
                $valid = $true; break
            } catch { Write-Warn2 $_.Exception.Message }
        }
        if (-not $valid) { throw (T 'Не удалось скачать проверенную модель. Файлы игры и активные модели не изменены; попробуйте применить патч позже.' 'Could not download a verified model. Game files and active models are unchanged; retry applying the patch later.') }
        [IO.File]::Move($temporary, $destination)
    } finally {
        $ProgressPreference = $oldProgress
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
function Clear-ModelPlan($plan) {
    if ($plan -and $plan.Stage -and (Test-Path -LiteralPath $plan.Stage)) {
        try { Remove-Item -LiteralPath $plan.Stage -Recurse -Force }
        catch { Write-Warn2 (T "Не удалось удалить временную папку: $($plan.Stage)" "Could not remove temporary folder: $($plan.Stage)") }
    }
}
function Add-ModelOperation($plan, [string]$path, $spec, [string]$source = '', [bool]$keepBackup = $true) {
    $oldHash = Get-ModelHash $path
    if (Test-ModelFile $path $spec) { return }
    if (-not $plan.Stage) {
        $plan.Stage = Join-Path $plan.Directory ('.swyf-model-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        New-Item -ItemType Directory -Path $plan.Stage | Out-Null
    }
    $temporary = Join-Path $plan.Stage ([Guid]::NewGuid().ToString('N') + '.gguf')
    if ($source) {
        [IO.File]::Copy($source, $temporary, $false)
        Assert-ModelFile $temporary $spec
    } else { Download-VerifiedModel $temporary $spec }
    [void]$plan.Operations.Add([pscustomobject]@{
        Path = $path; Spec = $spec; CurrentHash = $oldHash; Temporary = $temporary
        Backup = $path + '.swyf-before-repair-' + [Guid]::NewGuid().ToString('N')
        KeepBackup = $keepBackup; Applied = $false
    })
}
function Prepare-ModelSwitch([string]$kind = '') {
    if ($kind -and $kind -notin @('q8', 'q4')) { throw 'Model must be q8 or q4.' }
    $directory = Get-QwenModelDir -Create
    $active = Join-Path $directory $ModelSpecs.q8.Name
    $codec = Join-Path $directory $ModelSpecs.codec.Name
    Write-Info2 (T 'Проверяю SHA-256 активной модели и аудиокодека...' 'Checking active model and codec SHA-256...')
    $activeHash = Get-ModelHash $active
    $codecHash = Get-ModelHash $codec
    $currentKind = ''
    foreach ($candidate in @('q8', 'q4')) {
        if ($activeHash -eq $ModelSpecs[$candidate].Hash -and (Get-Item -LiteralPath $active).Length -eq $ModelSpecs[$candidate].Bytes) { $currentKind = $candidate; break }
    }
    $choicePath = Join-Path $directory 'swyf-model-choice.txt'
    if (-not $kind) {
        $kind = $currentKind
        if (-not $kind -and (Test-Path -LiteralPath $choicePath -PathType Leaf) -and (Get-Item -LiteralPath $choicePath).Length -le 64) {
            $saved = [IO.File]::ReadAllText($choicePath).Trim()
            if ($saved -in @('q4', 'q8')) { $kind = $saved }
        }
        # Older patchers did not save a selection. A full-size damaged Q4 is identifiable by size.
        if (-not $kind -and (Test-Path -LiteralPath $active -PathType Leaf) -and (Get-Item -LiteralPath $active).Length -eq $ModelSpecs.q4.Bytes) { $kind = 'q4' }
        if (-not $kind) {
            $kind = 'q8'
            Write-Warn2 (T 'Модель отсутствует или повреждена, прежний выбор неизвестен. Восстановлю стандартную Q8.' 'Model missing or corrupt; previous selection is unknown. Restoring standard Q8.')
        }
    }
    $plan = [pscustomobject]@{
        Kind = $kind; Directory = $directory; Stage = ''; ChoicePath = $choicePath
        Operations = (New-Object 'System.Collections.Generic.List[object]')
        Checks = @([pscustomobject]@{ Path = $active; Hash = $activeHash }, [pscustomobject]@{ Path = $codec; Hash = $codecHash })
    }
    try {
        # Stage every required replacement before committing any live file or DLL.
        if (-not (Test-ModelFile $codec $ModelSpecs.codec)) {
            Write-Warn2 (T 'Аудиокодек отсутствует или повреждён. Загружу проверенную копию.' 'Codec missing or corrupt. Downloading a verified copy.')
            Add-ModelOperation $plan $codec $ModelSpecs.codec
        }
        $cache = @{ q8 = (Join-Path $directory 'qwen-talker-0.6b-base-Q8_0.original.gguf'); q4 = (Join-Path $directory $ModelSpecs.q4.Name) }
        if ($currentKind -ne $kind) {
            # Preserve a healthy outgoing model for offline switching back.
            if ($currentKind) { Add-ModelOperation $plan $cache[$currentKind] $ModelSpecs[$currentKind] $active }
            $source = if (Test-ModelFile $cache[$kind] $ModelSpecs[$kind]) { $cache[$kind] } else { '' }
            Write-Info2 (T "Подготавливаю проверенную $kind..." "Preparing verified $kind...")
            Add-ModelOperation $plan $active $ModelSpecs[$kind] $source ([string]::IsNullOrEmpty($currentKind))
        }
        return $plan
    } catch { Clear-ModelPlan $plan; throw }
}
function Install-ModelOperation($operation) {
    if ((Get-ModelHash $operation.Path) -ne $operation.CurrentHash) { throw "Model changed during operation: $($operation.Path)" }
    if ($operation.CurrentHash) { [IO.File]::Replace($operation.Temporary, $operation.Path, $operation.Backup) }
    else { [IO.File]::Move($operation.Temporary, $operation.Path) }
    $operation.Applied = $true
    Assert-ModelFile $operation.Path $operation.Spec
}
function Undo-ModelOperations($plan) {
    $errors = New-Object 'System.Collections.Generic.List[string]'
    for ($i = $plan.Operations.Count - 1; $i -ge 0; $i--) {
        $operation = $plan.Operations[$i]
        if (-not $operation.Applied) { continue }
        try {
            if ((Get-ModelHash $operation.Path) -ne $operation.Spec.Hash) { throw "Model changed externally; rollback preserved it. Original backup: $($operation.Backup)" }
            if ($operation.CurrentHash) {
                if ((Get-ModelHash $operation.Backup) -ne $operation.CurrentHash) { throw "Model rollback backup mismatch: $($operation.Backup)" }
                [IO.File]::Replace($operation.Backup, $operation.Path, [NullString]::Value)
            } else { Remove-Item -LiteralPath $operation.Path }
            $operation.Applied = $false
        } catch { [void]$errors.Add($_.Exception.Message) }
    }
    if ($errors.Count) { throw ($errors -join '; ') }
}
function Complete-ModelSwitch($plan) {
    try {
        Assert-GameClosed
        foreach ($check in $plan.Checks) {
            if ((Get-ModelHash $check.Path) -ne $check.Hash) { throw "Model changed during preparation: $($check.Path)" }
        }
        foreach ($operation in $plan.Operations) { Assert-ModelFile $operation.Temporary $operation.Spec }
        try {
            foreach ($operation in $plan.Operations) {
                Assert-GameClosed
                Install-ModelOperation $operation
            }
        } catch {
            $failure = $_
            try { Undo-ModelOperations $plan } catch { Write-Warn2 $_.Exception.Message }
            throw $failure
        }
        # Preserve corrupt originals. Healthy outgoing weights already have a verified cache copy.
        foreach ($operation in $plan.Operations) {
            if (Test-Path -LiteralPath $operation.Backup) {
                if ($operation.KeepBackup) { Write-Host (T "Старый файл сохранён: $($operation.Backup)" "Previous file saved: $($operation.Backup)") }
                else { try { Remove-Item -LiteralPath $operation.Backup } catch { Write-Warn2 $_.Exception.Message } }
            }
        }
        try { [IO.File]::WriteAllText($plan.ChoicePath, $plan.Kind) }
        catch { Write-Warn2 (T 'Не удалось запомнить модель; проверенные файлы уже установлены.' 'Could not remember selection; verified model files are already installed.') }
        Write-Ok (T "Модель $($plan.Kind) и аудиокодек проверены и готовы." "Verified $($plan.Kind) model and codec are ready.")
    } finally { Clear-ModelPlan $plan }
}
