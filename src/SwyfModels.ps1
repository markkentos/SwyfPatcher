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
function Get-QwenModelDir {
    $directory = Join-Path (Get-ProfileDir) ('qwen3-tts/' + $ModelRevision)
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Model cache not found: $directory. Let the game download its models first." }
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
function Download-VerifiedModel([string]$destination, $spec) {
    $temporary = $destination + '.download-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $urls = @(
        "https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)",
        "https://hf-mirror.com/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)",
        "https://hf.aihoster.ru/Serveurperso/Qwen3-TTS-GGUF/resolve/$ModelRevision/$($spec.Name)"
    )
    $oldHash = if (Test-Path -LiteralPath $destination) { (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash } else { '' }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $valid = $false
        foreach ($url in $urls) {
            try {
                if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
                Write-Info2 (T "Загружаю $($spec.Name): $url" "Downloading $($spec.Name) from $url")
                Invoke-WebRequest -Uri $url -OutFile $temporary -UseBasicParsing -TimeoutSec 1800
                Assert-ModelFile $temporary $spec
                $valid = $true; break
            } catch { Write-Warn2 $_.Exception.Message }
        }
        if (-not $valid) { throw 'All downloads failed verification. Active model is unchanged.' }
        if ($oldHash) {
            if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $oldHash) { throw 'Model cache changed during download.' }
            $backup = $destination + '.before-download-' + [Guid]::NewGuid().ToString('N')
            [IO.File]::Replace($temporary, $destination, $backup)
        } else {
            # Move without overwrite: another downloader must not be clobbered.
            [IO.File]::Move($temporary, $destination)
        }
        Assert-ModelFile $destination $spec
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
function Prepare-ModelSwitch([string]$kind) {
    if ($kind -notin @('q8', 'q4')) { throw 'Model must be q8 or q4.' }
    if ($kind -eq 'q4') { Write-Info2 (T 'Q4 сохранит 4-битные веса. На Vulkan включится режим совместимости.' 'Q4 keeps its 4-bit weights. Vulkan will use the compatibility path.') }
    $directory = Get-QwenModelDir
    $active = Join-Path $directory $ModelSpecs.q8.Name
    $codec = Join-Path $directory $ModelSpecs.codec.Name
    Assert-ModelFile $codec $ModelSpecs.codec
    $spec = $ModelSpecs[$kind]
    $original = Join-Path $directory 'qwen-talker-0.6b-base-Q8_0.original.gguf'
    if (Test-ModelFile $active $spec) { return [pscustomobject]@{ Unchanged = $true; Kind = $kind } }
    if ($kind -eq 'q4') {
        if (-not (Test-ModelFile $original $ModelSpecs.q8)) {
            if (-not (Test-ModelFile $active $ModelSpecs.q8)) { throw 'A verified original Q8 model is required before switching to Q4. Choose Q8 first.' }
            if (Test-Path -LiteralPath $original) { throw "Invalid existing Q8 backup: $original. Preserve/move it and retry; it will not be overwritten." }
            [IO.File]::Copy($active, $original, $false)
            Assert-ModelFile $original $ModelSpecs.q8
        }
        $source = Join-Path $directory $spec.Name
    } else { $source = $original }
    if (-not (Test-ModelFile $source $spec)) { Download-VerifiedModel $source $spec }
    Assert-ModelFile $source $spec
    $currentHash = if (Test-Path -LiteralPath $active) { (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash } else { '' }
    return [pscustomobject]@{ Unchanged = $false; Kind = $kind; Source = $source; Active = $active; CurrentHash = $currentHash; Spec = $spec }
}
function Complete-ModelSwitch($plan) {
    if ($plan.Unchanged) { Write-Ok (T "Проверенная модель $($plan.Kind) уже включена." "Verified model $($plan.Kind) is already active."); return }
    Assert-GameClosed
    $temporary = $plan.Active + '.swyf-model-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::Copy($plan.Source, $temporary, $false)
        Assert-ModelFile $temporary $plan.Spec
        if ($plan.CurrentHash) {
            if ((Get-FileHash -LiteralPath $plan.Active -Algorithm SHA256).Hash -ne $plan.CurrentHash) { throw 'Active model changed during operation. No model replacement.' }
            [IO.File]::Replace($temporary, $plan.Active, [NullString]::Value)
        } else { [IO.File]::Move($temporary, $plan.Active) }
        Assert-ModelFile $plan.Active $plan.Spec
        Write-Ok (T "Проверенная модель $($plan.Kind) включена." "Verified $($plan.Kind) model activated.")
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}
