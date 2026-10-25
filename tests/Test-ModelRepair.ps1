$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/SwyfPatch.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('swyf-repair-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$checks = 0
function Assert($value, [string]$message) { if (-not $value) { throw "ASSERT: $message" }; $script:checks++ }
function Throws([scriptblock]$action, [string]$message) {
    $threw = $false; try { & $action | Out-Null } catch { $threw = $true }
    Assert $threw $message
}
function Assert-GameClosed { }
function Get-ProfileDir { $script:profile }
$script:contents = @{
    q8 = [Text.Encoding]::UTF8.GetBytes('verified-q8-fixture-original')
    q4 = [Text.Encoding]::UTF8.GetBytes('verified-q4-fixture')
    codec = [Text.Encoding]::UTF8.GetBytes('verified-codec-fixture')
}
foreach ($key in @('q8', 'q4', 'codec')) {
    $ModelSpecs[$key] = @{ Name = $ModelSpecs[$key].Name; Bytes = $contents[$key].Length; Hash = (Sha256Hex $contents[$key]) }
}
function New-Case([string]$name) {
    $script:profile = Join-Path $root $name
    $script:cache = Join-Path $profile ('qwen3-tts/' + $ModelRevision)
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $script:active = Join-Path $cache $ModelSpecs.q8.Name
    $script:codec = Join-Path $cache $ModelSpecs.codec.Name
    $script:original = Join-Path $cache 'qwen-talker-0.6b-base-Q8_0.original.gguf'
    $script:q4cache = Join-Path $cache $ModelSpecs.q4.Name
    $script:choice = Join-Path $cache 'swyf-model-choice.txt'
    $script:requests = New-Object 'System.Collections.Generic.List[string]'
    $script:network = 'ok'
}
function Good([string]$path, [string]$kind) { [IO.File]::WriteAllBytes($path, $contents[$kind]) }
function Bad([string]$path, [int]$length = 17757) { [IO.File]::WriteAllBytes($path, (New-Object byte[] $length)) }
function Clean {
    Assert (@(Get-ChildItem -LiteralPath $cache -Force | Where-Object { $_.Name -like '*.tmp' }).Count -eq 0) 'Private staging removed'
}
function BackedUp([string]$path, [string]$hash) {
    $matches = @(Get-ChildItem -LiteralPath $cache -File | Where-Object { $_.FullName.StartsWith($path + '.swyf-before-repair-') -and (Get-ModelHash $_.FullName) -eq $hash })
    Assert ($matches.Count -eq 1) 'Corrupt original retained byte-for-byte'
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    [void]$script:requests.Add([string]$Uri)
    $kind = @('q8','q4','codec') | Where-Object { $Uri.EndsWith('/' + $ModelSpecs[$_].Name) } | Select-Object -First 1
    if (-not $kind) { throw 'Unexpected test URL' }
    if ($network -eq 'offline' -or ($network -eq 'fail-q8' -and $kind -eq 'q8')) { throw 'Simulated network interruption' }
    if ($network -eq 'html' -or ($network -eq 'mirror' -and $Uri.StartsWith('https://huggingface.co/'))) { [IO.File]::WriteAllText($OutFile, '<html>HTTP 200 error page</html>'); return }
    if ($network -eq 'wrong-hash') { [IO.File]::WriteAllBytes($OutFile, (New-Object byte[] $ModelSpecs[$kind].Bytes)); return }
    Good $OutFile $kind
}
$realInstall = ${function:Install-ModelOperation}
try {
    New-Case 'healthy-q8'
    Good $active q8; Good $codec codec; Bad $q4cache
    $before = (Get-Item -LiteralPath $active).LastWriteTimeUtc
    $plan = Prepare-ModelSwitch
    Assert ($plan.Kind -eq 'q8' -and $plan.Operations.Count -eq 0) 'Healthy Q8 and codec need no replacement'
    Complete-ModelSwitch $plan
    Assert ($requests.Count -eq 0 -and (Get-Item -LiteralPath $active).LastWriteTimeUtc -eq $before) 'Healthy files untouched and no downloads of unused Q4'
    Assert ([IO.File]::ReadAllText($choice) -eq 'q8') 'Healthy selection remembered'
    Clean

    New-Case 'healthy-q4'
    Good $active q4; Good $codec codec
    Complete-ModelSwitch (Prepare-ModelSwitch)
    Assert ((Test-ModelFile $active $ModelSpecs.q4) -and $requests.Count -eq 0) 'Q4 content under Q8 filename preserved'
    Assert ([IO.File]::ReadAllText($choice) -eq 'q4') 'Q4 selection persisted'
    Bad $active 5; $old = Get-ModelHash $active
    $plan = Prepare-ModelSwitch
    Assert ($plan.Kind -eq 'q4') 'Remembered Q4 survives truncation'
    Complete-ModelSwitch $plan
    Assert ($requests.Count -eq 1 -and $requests[0].EndsWith($ModelSpecs.q4.Name)) 'Redownload only selected Q4'
    BackedUp $active $old
    Clean

    New-Case 'codec-only'
    Good $active q4; Bad $codec 17770; $old = Get-ModelHash $codec
    $plan = Prepare-ModelSwitch
    Assert ((Get-ModelHash $codec) -eq $old) 'Preparation does not overwrite corrupt codec before all downloads finish'
    Complete-ModelSwitch $plan
    Assert ($requests.Count -eq 1 -and (Test-ModelFile $active $ModelSpecs.q4) -and (Test-ModelFile $codec $ModelSpecs.codec)) 'Codec repaired without changing Q4'
    BackedUp $codec $old
    Clean

    New-Case 'reported-17kb-pair'
    Bad $active 17757; Bad $codec 17770
    $oldActive = Get-ModelHash $active; $oldCodec = Get-ModelHash $codec
    $plan = Prepare-ModelSwitch
    Assert ($plan.Kind -eq 'q8' -and $requests.Count -eq 2) 'Unidentifiable truncated model defaults to Q8; both files downloaded'
    Assert ((Get-ModelHash $active) -eq $oldActive -and (Get-ModelHash $codec) -eq $oldCodec) 'Both live files unchanged during preparation'
    Complete-ModelSwitch $plan
    Assert ((Test-ModelFile $active $ModelSpecs.q8) -and (Test-ModelFile $codec $ModelSpecs.codec)) 'Reported pair repaired with exact hashes'
    BackedUp $active $oldActive; BackedUp $codec $oldCodec
    Clean
    $script:requests.Clear()
    Complete-ModelSwitch (Prepare-ModelSwitch)
    Assert ($requests.Count -eq 0) 'Reapplying after repair makes no downloads'

    New-Case 'no-cache'
    Remove-Item -LiteralPath $profile -Recurse -Force
    Complete-ModelSwitch (Prepare-ModelSwitch)
    Assert ($requests.Count -eq 2 -and (Test-ModelFile $active $ModelSpecs.q8) -and (Test-ModelFile $codec $ModelSpecs.codec)) 'Fresh install creates cache and downloads required pair'
    Clean

    New-Case 'q8-backup'
    Bad $active; Bad $codec; Good $original q8
    Complete-ModelSwitch (Prepare-ModelSwitch)
    Assert ($requests.Count -eq 1 -and $requests[0].EndsWith($ModelSpecs.codec.Name)) 'Valid Q8 backup reused without network model download'
    Assert (Test-ModelFile $active $ModelSpecs.q8) 'Backup activates as a verified copy'

    New-Case 'explicit-fresh-q4'
    Complete-ModelSwitch (Prepare-ModelSwitch q4)
    Assert ($requests.Count -eq 2 -and (Test-ModelFile $active $ModelSpecs.q4)) 'Explicit Q4 on fresh cache downloads Q4 and codec only'

    New-Case 'same-size-q4'
    Bad $active $ModelSpecs.q4.Bytes; Good $codec codec
    $plan = Prepare-ModelSwitch
    Assert ($plan.Kind -eq 'q4') 'Old installation can recover full-size corrupt Q4 without saved selection'
    Complete-ModelSwitch $plan
    Assert (Test-ModelFile $active $ModelSpecs.q4) 'Same-size corruption replaced after hash verification'

    New-Case 'offline-switch'
    Good $active q8; Good $codec codec; Good $q4cache q4; Bad $original 3
    $badBackup = Get-ModelHash $original
    $script:network = 'offline'
    Complete-ModelSwitch (Prepare-ModelSwitch q4)
    Assert ((Test-ModelFile $original $ModelSpecs.q8) -and (Test-ModelFile $active $ModelSpecs.q4)) 'Outgoing Q8 saved even if old backup was corrupt'
    BackedUp $original $badBackup
    Remove-Item -LiteralPath $q4cache
    Complete-ModelSwitch (Prepare-ModelSwitch q8)
    Assert ((Test-ModelFile $q4cache $ModelSpecs.q4) -and (Test-ModelFile $active $ModelSpecs.q8) -and $requests.Count -eq 0) 'Outgoing Q4 saved; offline switch back to Q8 succeeds'
    Clean

    foreach ($mode in @('html', 'wrong-hash', 'offline', 'fail-q8')) {
        New-Case $mode
        Bad $active 17757; Bad $codec 17770
        $oldActive = Get-ModelHash $active; $oldCodec = Get-ModelHash $codec
        $script:network = $mode
        Throws { Prepare-ModelSwitch } "$mode cannot install unchecked content"
        Assert ((Get-ModelHash $active) -eq $oldActive -and (Get-ModelHash $codec) -eq $oldCodec) "$mode preserves both live files"
        Assert (-not (Test-Path -LiteralPath $choice)) "$mode does not save a failed selection"
        Clean
    }

    New-Case 'verified-mirror'
    $script:network = 'mirror'
    Complete-ModelSwitch (Prepare-ModelSwitch)
    Assert ($requests.Count -eq 4 -and (Test-ModelFile $active $ModelSpecs.q8) -and (Test-ModelFile $codec $ModelSpecs.codec)) 'HTML from primary is rejected; verified mirror downloads accepted'
    Assert (@($requests | Where-Object { $_ -notmatch [regex]::Escape($ModelRevision) }).Count -eq 0) 'All downloads pin the supported revision'
    Clean

    foreach ($after in @($false, $true)) {
        New-Case ('commit-failure-' + $after)
        Bad $active; Bad $codec
        $oldActive = Get-ModelHash $active; $oldCodec = Get-ModelHash $codec
        $plan = Prepare-ModelSwitch
        $script:failAfter = $after
        function Install-ModelOperation($operation) {
            if ($operation.Path -eq $active -and -not $script:failAfter) { throw 'Simulated replacement failure' }
            & $realInstall $operation
            if ($operation.Path -eq $active -and $script:failAfter) { throw 'Simulated post-replacement failure' }
        }
        Throws { Complete-ModelSwitch $plan } 'Replacement failure is reported'
        Assert ((Get-ModelHash $active) -eq $oldActive -and (Get-ModelHash $codec) -eq $oldCodec) 'Partial model transaction rolled back'
        Assert (-not (Test-Path -LiteralPath $choice)) 'Failed commit does not change selection'
        Clean
        Set-Item Function:Install-ModelOperation $realInstall
    }

    New-Case 'concurrent-before-commit'
    Bad $active; Bad $codec
    $oldCodec = Get-ModelHash $codec
    $plan = Prepare-ModelSwitch
    [IO.File]::WriteAllText($active, 'another downloader')
    Throws { Complete-ModelSwitch $plan } 'Concurrent model change aborts before commit'
    Assert ([IO.File]::ReadAllText($active) -eq 'another downloader' -and (Get-ModelHash $codec) -eq $oldCodec) 'Concurrent contents preserved and codec unchanged'
    Clean

    New-Case 'concurrent-during-commit'
    Bad $active; Bad $codec
    $oldCodec = Get-ModelHash $codec
    $plan = Prepare-ModelSwitch
    function Install-ModelOperation($operation) {
        & $realInstall $operation
        if ($operation.Path -eq $active) { [IO.File]::WriteAllText($active, 'foreign concurrent write'); throw 'Simulated concurrent write' }
    }
    Throws { Complete-ModelSwitch $plan } 'Concurrent change after replacement is reported'
    Assert ([IO.File]::ReadAllText($active) -eq 'foreign concurrent write') 'Rollback does not clobber concurrent write'
    Assert ((Get-ModelHash $codec) -eq $oldCodec) 'Independent codec rollback still completed'
    Clean
    Set-Item Function:Install-ModelOperation $realInstall
    Write-Host "PASS: $checks model repair assertions; all downloads mocked and writes confined to temporary profiles."
} finally {
    Set-Item Function:Install-ModelOperation $realInstall
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
