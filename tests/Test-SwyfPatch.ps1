param(
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [string]$OldOriginal = '',
    [string]$PreviousWorker = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/SwyfPatch.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('swyf-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "ASSERT: $message" }
    $script:checks++
}
function Assert-Throws([scriptblock]$operation, [string]$message) {
    $threw = $false
    try { & $operation | Out-Null } catch { $threw = $true }
    Assert $threw $message
}
function Make-Context([byte[]]$bytes, $build) {
    return [pscustomobject]@{ Current = $bytes; CurHash = (Sha256Hex $bytes); Build = $build; Already = $false; CurVariant = ''; Legacy = $false }
}
try {
    $managedSource = Join-Path $GameRoot ($GameName + '_Data/Managed')
    $original = [IO.File]::ReadAllBytes((Join-Path $managedSource 'Assembly-CSharp.dll.swyf.original'))
    $build = $Builds[0]
    Assert ((Sha256Hex $original) -eq $build.Original) 'Correct supplied original fixture'
    $liveBefore = (Get-FileHash -LiteralPath (Join-Path $managedSource 'Assembly-CSharp.dll')).Hash
    $game = Join-Path $testRoot 'Game with spaces'
    $managed = Join-Path $game ($GameName + '_Data/Managed')
    New-Item -ItemType Directory -Path $managed -Force | Out-Null
    foreach ($name in @('ScriptsAssDef.dll', 'Kolkata.Speech.dll')) { Copy-Item -LiteralPath (Join-Path $managedSource $name) -Destination $managed }
    $runtimeSource = Get-RuntimeDir $GameRoot
    $runtime = Get-RuntimeDir $game
    New-Item -ItemType Directory -Path (Join-Path $runtime 'gpu') -Force | Out-Null
    foreach ($name in @('QwenTtsWorker.exe') + @($RuntimeSpec.Dependencies.Keys)) {
        Copy-Item -LiteralPath (Join-Path $runtimeSource $name) -Destination (Join-Path $runtime $name)
    }
    $workerPath = Join-Path $runtime 'QwenTtsWorker.exe'
    $liveWorkerBefore = (Get-FileHash -LiteralPath (Join-Path $runtimeSource 'QwenTtsWorker.exe')).Hash
    $dll = Join-Path $managed 'Assembly-CSharp.dll'
    $states = New-Object 'System.Collections.Generic.List[object]'
    $states.Add(@{ Name = 'original'; Bytes = $original })
    foreach ($backend in @('auto', 'cpu', 'vulkan')) {
        foreach ($reference in @(3, 10)) {
            $plan = Get-PatchPlan (Make-Context $original $build) $backend $reference
            $states.Add(@{ Name = "$backend-ref$reference"; Bytes = $plan.Output })
            if ($reference -eq 3) {
                $old = [byte[]]$plan.Output.Clone(); $old[0x8AF8F] = 0x8F
                Assert ($LegacyPatched[$build.Original].ContainsKey((Sha256Hex $old))) 'Recognize v2.8 output hash'
                $states.Add(@{ Name = "v28-$backend"; Bytes = $old })
            }
        }
    }
    foreach ($state in $states) {
        [IO.File]::WriteAllBytes($dll, $state.Bytes)
        $ctx = Get-Context $game
        foreach ($backend in @('auto', 'cpu', 'vulkan')) {
            foreach ($reference in @(3, 10)) {
                $plan = Get-PatchPlan $ctx $backend $reference
                Assert ((Sha256Hex $plan.Source) -eq $build.Original) "$($state.Name): exact original reconstruction"
                Assert ($plan.Output[0x8AF8F] -eq 0xAC) "$($state.Name): valid startup branch"
                Assert ($plan.Output[0x8BA06] -eq $reference) "$($state.Name): reference selection"
            }
        }
    }
    if ($OldOriginal) {
        $oldBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $OldOriginal).Path)
        foreach ($backend in @('auto', 'cpu', 'vulkan')) {
            foreach ($reference in @(3, 10)) {
                $plan = Get-PatchPlan (Make-Context $oldBytes $Builds[1]) $backend $reference
                Assert ((Sha256Hex $plan.Source) -eq $Builds[1].Original) '22 Oct original reconstruction'
                Assert ($plan.Output[0x1213AF] -eq 0xAC) '22 Oct startup branch corrected'
                Assert ($plan.Output[0x121E26] -eq $reference) '22 Oct reference selection'
            }
        }
    }
    Write-Host 'PASS: originals, v2.8, startup hotfix and reference-test migrations; 3 backends x 2 references.'

    # All writes below target temporary fixtures; Windows process/registry APIs are mocked.
    function Assert-GameClosed { }
    function Set-VoicePreference { }
    [IO.File]::WriteAllBytes($dll, $states[2].Bytes)
    $stale = Join-Path $managed 'Assembly-CSharp.dll.swyf.original'
    [IO.File]::WriteAllText($stale, 'STALE BACKUP - PRESERVE')
    Invoke-Patch (Get-Context $game) 'cpu' 10
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.PatchedWorker) 'Runtime worker installed with verified hash'
    Assert ((Get-FileHash -LiteralPath ($workerPath + '.swyf.original')).Hash -eq $RuntimeSpec.OriginalWorker) 'Original worker backup preserved'
    Assert ((Get-Context $game).CurVariant -eq 'cpu') 'CPU written atomically'
    Assert ((Get-Context $game).ReferenceSeconds -eq 10) '10s default state detected'
    Assert ([IO.File]::ReadAllText($stale) -eq 'STALE BACKUP - PRESERVE') 'Stale backup preserved'
    Invoke-Patch (Get-Context $game) 'vulkan' 3
    Assert ((Get-Context $game).CurVariant -eq 'vulkan') 'Backend switching works on current DLL'
    $hashBeforeCheck = (Get-FileHash -LiteralPath $dll).Hash
    Invoke-Check (Get-Context $game) 'cpu' 10 'q4'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $hashBeforeCheck) 'Check with model option leaves DLL untouched'
    Invoke-Restore (Get-Context $game)
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Restore also restores original worker'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Restore ignores stale backup and restores exact original'
    $bad = [byte[]]$original.Clone(); $bad[0] = 0
    [IO.File]::WriteAllBytes($dll, $bad)
    Assert-Throws { Get-Context $game } 'Unknown DLL rejected'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq (Sha256Hex $bad)) 'Unknown DLL unchanged'
    [IO.File]::WriteAllBytes($dll, $original)
    $ctx = Get-Context $game; $plan = Get-PatchPlan $ctx 'auto' 10
    [IO.File]::WriteAllBytes($dll, $bad)
    Assert-Throws { ReplaceVerified $dll $ctx.Current $plan.Output $plan.Hash } 'Concurrent DLL change rejected'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq (Sha256Hex $bad)) 'Concurrent content preserved'
    [IO.File]::WriteAllBytes($dll, $original)
    Write-Host 'PASS: actual temporary DLL writes, dry-run, stale backup, restoration, unsupported and concurrent changes.'

    $options = Convert-Options -Arguments @('--backend', 'cpu', '--model', 'q4', '--check', $game)
    Assert ($options.Cli -and $options.Action -eq 'check' -and $options.Model -eq 'q4') 'GNU-style flags parsed'
    Assert ((Convert-Options -Arguments @('-Backend', 'vulkan', '-NonInteractive', '-GamePath', $game)).Backend -eq 'vulkan') 'PowerShell-style flags parsed'
    Assert ((Convert-Options -Arguments @('--backend', 'cpu')).Cli) 'Backend-only invocation is CLI'
    Assert (-not (Convert-Options -Arguments @($game)).Cli) 'Folder drag opens menu'
    foreach ($badArguments in @(@('--model', 'q4', '--restore'), @('--launch', '--backend', 'cpu'), @('--check', '--restore'), @('--backend'), @('--reference', '4'), @('--unknown'))) {
        Assert-Throws { Convert-Options -Arguments $badArguments } 'Invalid/conflicting flags rejected before writes'
    }
    Assert ((Convert-Options -Arguments @('--lang', 'en')).Lang -eq 'en') 'English override parsed'
    Assert (-not (Convert-Options -Arguments @('--lang', 'ru')).Cli) 'Language alone still opens menu'
    Assert-Throws { Convert-Options -Arguments @('--lang', 'de') } 'Unsupported language rejected'
    $realInvokeAction = ${function:Invoke-Action}
    $script:dispatches = New-Object 'System.Collections.Generic.List[object]'
    function Invoke-Action([string]$game, [string]$action, [string]$backend = '', [int]$reference = 0, [string]$model = '') {
        $script:dispatches.Add(@{ Action = $action; Backend = $backend; Reference = $reference; Model = $model })
    }
    Invoke-MenuAction $game '1'
    Assert ($dispatches.Count -eq 1 -and $dispatches[0].Action -eq 'check') 'Status action does not patch'
    Invoke-MenuAction $game '2'
    Assert ($dispatches.Count -eq 2 -and $dispatches[1].Action -eq 'patch' -and $dispatches[1].Model -eq '') 'Apply preserves selected model'
    Invoke-MenuAction $game '3'
    Assert ($dispatches[-1].Backend -eq 'cpu' -and $dispatches[-1].Model -eq '') 'CPU switch preserves selected model'
    Invoke-MenuAction $game '4'
    Assert ($dispatches[-1].Backend -eq 'vulkan' -and $dispatches[-1].Model -eq '') 'GPU switch preserves selected model'
    Invoke-MenuAction $game '5'
    Assert ($dispatches[-1].Model -eq 'q4' -and $dispatches[-1].Backend -eq '') 'Direct Q4 choice preserves backend'
    Invoke-MenuAction $game '6'
    Assert ($dispatches[-1].Model -eq 'q8') 'Direct Q8 choice'
    Invoke-MenuAction $game '7'
    Assert ($dispatches[-1].Action -eq 'launch' -and $dispatches.Count -eq 7) 'Launch does not patch'
    foreach ($choice in @('invalid', '9', '10', '')) { Assert-Throws { Invoke-MenuAction $game $choice } 'Invalid main menu choice cannot patch' }
    Assert ($dispatches.Count -eq 7) 'Invalid choices have no action'
    $realPatcherRoot = $PatcherRoot
    $script:PatcherRoot = Join-Path $testRoot 'language-test'
    New-Item -ItemType Directory -Path $PatcherRoot | Out-Null
    Initialize-Language 'ru'
    Assert ((T 'русский' 'English') -eq 'русский') 'Russian strings selected'
    $ruMenu = (Show-MainMenu 6>&1 | Out-String)
    Assert (@([regex]::Matches($ruMenu, '\[[0-8]\]')).Count -eq 9 -and $ruMenu -notmatch 'Дополнительно') 'Russian menu is flat with 9 choices including Exit'
    Invoke-MenuAction $game '8'
    Assert ($Language -eq 'en' -and $dispatches.Count -eq 7) 'Language switch never patches game'
    Initialize-Language
    Assert ((T 'русский' 'English') -eq 'English') 'Language preference survives reinitialization'
    $enMenu = (Show-MainMenu 6>&1 | Out-String)
    Assert ($enMenu -match 'Check current status' -and $enMenu -match 'Switch to GPU' -and $enMenu -notmatch 'Проверить') 'English menu translated'
    Assert (@([regex]::Matches($enMenu, '\[[0-8]\]')).Count -eq 9) 'English menu has 9 choices including Exit'
    $script:PatcherRoot = $realPatcherRoot
    Set-Item -Path Function:Invoke-Action -Value $realInvokeAction
    Write-Host 'PASS: command line, flat bilingual menu and dispatch isolation.'

    # Refuse mismatched native runtimes before altering either executable or game DLL.
    $nativePath = Join-Path $runtime 'qwen3.dll'
    $nativeBytes = [IO.File]::ReadAllBytes($nativePath)
    [IO.File]::WriteAllText($nativePath, 'incompatible runtime')
    Assert-Throws { Invoke-Patch (Get-Context $game) 'vulkan' 10 } 'Unknown native ABI is rejected before patching'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Native ABI rejection leaves game DLL unchanged'
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Native ABI rejection leaves worker unchanged'
    [IO.File]::WriteAllBytes($nativePath, $nativeBytes)
    $originalWorkerBytes = [IO.File]::ReadAllBytes($workerPath)
    [IO.File]::WriteAllText($workerPath, 'unknown worker')
    Assert-Throws { Get-RuntimePlan $game } 'Unknown worker preserved'
    Assert ([IO.File]::ReadAllText($workerPath) -eq 'unknown worker') 'Worker validation has no side effects'
    [IO.File]::WriteAllBytes($workerPath, $originalWorkerBytes)

    # Optional real fixture from the previously distributed local package.
    if ($PreviousWorker) {
        $previousBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $PreviousWorker).Path)
        $previousHash = Sha256Hex $previousBytes
        Assert ($previousHash -in $RuntimeSpec.PreviousWorkers) 'Previous worker fixture is explicitly supported'
        $backupPath = $workerPath + '.swyf.original'
        [IO.File]::WriteAllBytes($backupPath, $originalWorkerBytes)
        [IO.File]::WriteAllBytes($workerPath, $previousBytes)
        $runtimePlan = Get-RuntimePlan $game
        Assert ($runtimePlan.CurHash -eq $previousHash -and $runtimePlan.Hash -eq $RuntimeSpec.PatchedWorker) 'Previous worker plans upgrade to this release'
        Set-RuntimePlan $runtimePlan
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.PatchedWorker) 'Previous worker upgrade installs current payload'
        Assert ((Get-FileHash -LiteralPath $backupPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Previous worker upgrade preserves original backup'
        [IO.File]::WriteAllBytes($workerPath, $previousBytes)
        Set-RuntimePlan (Get-RuntimePlan $game $true)
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Previous worker can be restored directly'
        [IO.File]::WriteAllBytes($workerPath, $previousBytes)
        Remove-Item -LiteralPath $backupPath
        Assert-Throws { Get-RuntimePlan $game } 'Previous worker without original backup is rejected'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $previousHash) 'Rejected upgrade preserves previous worker'
        Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Worker migration leaves game DLL unchanged'
        [IO.File]::WriteAllBytes($workerPath, $originalWorkerBytes)
        [IO.File]::WriteAllBytes($backupPath, $originalWorkerBytes)
        Write-Host 'PASS: previous local worker upgrade, direct restore and missing-backup refusal.'
    }

    # Exercise model transactions with small deterministic files, never with user models.
    $script:testProfile = Join-Path $testRoot 'profile'
    function Get-ProfileDir { return $script:testProfile }
    $cache = Join-Path $testProfile ('qwen3-tts/' + $ModelRevision)
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $realSpecs = $ModelSpecs
    $script:ModelSpecs = @{}
    foreach ($kind in @('q8', 'q4', 'codec')) {
        $bytes = [Text.Encoding]::UTF8.GetBytes(("fixture-$kind" + $(if ($kind -eq 'q8') { '-original' })))
        $script:ModelSpecs[$kind] = @{ Name = $realSpecs[$kind].Name; Bytes = $bytes.Length; Hash = (Sha256Hex $bytes) }
        [IO.File]::WriteAllBytes((Join-Path $cache $ModelSpecs[$kind].Name), $bytes)
    }
    $active = Join-Path $cache $ModelSpecs.q8.Name
    Complete-ModelSwitch (Prepare-ModelSwitch 'q4')
    Assert (Test-ModelFile $active $ModelSpecs.q4) 'Verified Q4 activated'
    Assert (Test-ModelFile (Join-Path $cache 'qwen-talker-0.6b-base-Q8_0.original.gguf') $ModelSpecs.q8) 'Q8 backup verified'
    Invoke-MenuAction $game '6'
    Assert (Test-ModelFile $active $ModelSpecs.q8) 'Direct Q8 action restores Q8 exactly after Q4'
    Assert ((Get-Context $game).ReferenceSeconds -eq 10) 'Model switch installs 10s reference'
    Assert ((Get-Context $game).CurVariant -eq 'auto') 'Model switch selects auto on original DLL'
    Invoke-Restore (Get-Context $game)
    $q4 = Join-Path $cache $ModelSpecs.q4.Name
    [IO.File]::WriteAllText($q4, 'partial')
    function Invoke-WebRequest { param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec); [IO.File]::WriteAllText($OutFile, 'partial download'); throw 'Simulated interrupted download' }
    Assert-Throws { Prepare-ModelSwitch 'q4' } 'Interrupted or invalid model download rejected'
    Assert (Test-ModelFile $active $ModelSpecs.q8) 'Failed model download preserves active Q8'
    Assert (@(Get-ChildItem -LiteralPath $cache -Filter '*.tmp').Count -eq 0) 'Incomplete download temporary files cleaned'
    Write-Host 'PASS: model activation, verified Q8 backup and failed-download preservation.'

    $script:PatcherRoot = Join-Path $testRoot 'patcher'
    $logFolder = New-DiagnosticFolder 'test'
    [IO.File]::WriteAllText((Join-Path $logFolder 'Player.log'), "[SpeechRequest] provider=qwen stage=first_audio`n[SpeechRequest] provider=qwen stage=completed succeeded=True firstAudio=True cancelled=False`n[SpeechRequest] provider=qwen stage=completed succeeded=False firstAudio=True cancelled=True`n[Speech] No audio progress.`nException=none`nInvalidOperationException: current failure`n")
    foreach ($name in @('before-Player.log', 'after-Player.log', 'Player-prev.log')) {
        [IO.File]::WriteAllText((Join-Path $logFolder $name), "NullReferenceException: old startup crash`n[SpeechRequest] provider=qwen stage=completed succeeded=False cancelled=False`n")
    }
    New-Item -ItemType Directory -Path (Join-Path $logFolder 'qwen-worker') | Out-Null
    [IO.File]::WriteAllText((Join-Path $logFolder 'qwen-worker/qwen-current.log'), "LOAD backend=Vulkan0 q4GpuCompatibility=True`nPROFILE GGML_VK_DISABLE_F16=1`nCOMPLETE request=1`n")
    Write-DiagnosticReport $game $logFolder
    Complete-Diagnostics $logFolder
    Assert (Test-Path -LiteralPath ($logFolder + '.zip')) 'Diagnostic ZIP created'
    $summary = Get-Content -LiteralPath (Join-Path $logFolder 'speech-summary.txt') -Raw
    Assert ($summary -match 'CURRENT QWEN WORKER' -and $summary -match 'q4GpuCompatibility=True') 'Current native worker profile included in summary'
    Assert ($summary -match 'No audio progress') 'Speech summary captures stalled audio'
    Assert ($summary -match 'succeeded=1; cancelled=1; failed=0; first_audio=1') 'Summary counts only current Qwen requests, separates cancellation'
    Assert ($summary -notmatch 'NullReferenceException|old startup crash|Exception=none') 'Summary excludes old crashes and exception=none noise'
    Assert ($summary -match 'InvalidOperationException: current failure') 'Summary retains current exceptions'
    Assert ($summary -match 'before-Player.log' -and $summary -match 'HISTORICAL') 'Historical filenames clearly labelled'
    $report = Get-Content -LiteralPath (Join-Path $logFolder 'system-and-dll.txt') -Raw
    Assert ($report -match 'ACTIVE TALKER: verified q8') 'Report identifies active model by hash, not filename'
    [IO.File]::WriteAllText((Join-Path $cache $ModelSpecs.q4.Name), 'fixture-q4')
    Complete-ModelSwitch (Prepare-ModelSwitch 'q4')
    Write-DiagnosticReport $game $logFolder
    $report = Get-Content -LiteralPath (Join-Path $logFolder 'system-and-dll.txt') -Raw
    Assert ($report -match 'ACTIVE TALKER: verified q4') 'Q4 content under Q8 filename is clearly reported'
    Remove-Item -LiteralPath (Join-Path $logFolder 'Player.log')
    Write-SpeechSummary $logFolder
    $summary = Get-Content -LiteralPath (Join-Path $logFolder 'speech-summary.txt') -Raw
    Assert ($summary -match 'Player.log is missing' -and $summary -notmatch 'NullReferenceException|Qwen requests:') 'Missing current log never substitutes stale results'
    $script:ModelSpecs = $realSpecs
    [IO.File]::WriteAllText((Join-Path $game ($GameName + '.exe')), 'not executed: mocked launcher fixture')
    $savedLogEnv = [Environment]::GetEnvironmentVariable('SWYF_QWEN_LOG_DIR')
    $savedCaptureEnv = [Environment]::GetEnvironmentVariable('SWYF_QWEN_CAPTURE')
    try {
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_LOG_DIR', 'prior-log-setting')
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_CAPTURE', 'prior-capture-setting')
        $script:observedWorkerLog = ''
        $script:observedCapture = ''
        function Start-Process {
            param($FilePath, $WorkingDirectory, $ArgumentList, [switch]$PassThru)
            $script:observedWorkerLog = [Environment]::GetEnvironmentVariable('SWYF_QWEN_LOG_DIR')
            $script:observedCapture = [Environment]::GetEnvironmentVariable('SWYF_QWEN_CAPTURE')
            throw 'Simulated launch failure'
        }
        Assert-Throws { Invoke-TestLaunch $game } 'Launch failure is reported'
        Assert ($observedWorkerLog -like '*qwen-worker' -and $observedCapture -eq '1') 'Per-run worker logs and audio capture passed to child'
        Assert ([Environment]::GetEnvironmentVariable('SWYF_QWEN_LOG_DIR') -eq 'prior-log-setting') 'Worker log environment restored after launch failure'
        Assert ([Environment]::GetEnvironmentVariable('SWYF_QWEN_CAPTURE') -eq 'prior-capture-setting') 'Capture environment restored after launch failure'
    } finally {
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_LOG_DIR', $savedLogEnv)
        [Environment]::SetEnvironmentVariable('SWYF_QWEN_CAPTURE', $savedCaptureEnv)
    }
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Diagnostics did not patch DLL'
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtimeSource 'QwenTtsWorker.exe')).Hash -eq $liveWorkerBefore) 'User game worker unchanged throughout tests'
    Assert ((Get-FileHash -LiteralPath (Join-Path $managedSource 'Assembly-CSharp.dll')).Hash -eq $liveBefore) 'User game DLL unchanged throughout tests'
    Write-Host "PASS: $checks assertions. All mutable fixtures were under $testRoot"
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
