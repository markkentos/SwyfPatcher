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
    $managedSource = Join-Path $GameRoot ($GameName + '_Data/Managed')
    # The fixture original may live under any supported backup suffix; prefer the newest build.
    $build = $null; $fixturePath = $null
    foreach ($candidate in $Builds) {
        foreach ($suffix in @('.swyf.original', '.swyf-v23.original', '.swyf-v22.original', ('.swyf.' + $candidate.Original.Substring(0, 12) + '.original'))) {
            $path = Join-Path $managedSource ('Assembly-CSharp.dll' + $suffix)
            if ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path).Hash -eq $candidate.Original) { $build = $candidate; $fixturePath = $path; break }
        }
        if ($build) { break }
    }
    if (-not $build) { throw "No backup fixture matching a supported build was found in $managedSource." }
    $original = [IO.File]::ReadAllBytes($fixturePath)
    Assert ((Sha256Hex $original) -eq $build.Original) 'Correct supplied original fixture'
    $verifyEdit = @($build.Edits | Where-Object { $_.d -like 'Model verification*' } | Select-Object -First 1)
    $startupBranch = if ($verifyEdit) { $verifyEdit.o + 3 } else { $null }
    $referenceOffset = (@($build.Edits | Where-Object { $_.Reference })[0]).o
    $liveBefore = (Get-FileHash -LiteralPath (Join-Path $managedSource 'Assembly-CSharp.dll')).Hash
    $game = Join-Path $testRoot 'Game with spaces'
    $managed = Join-Path $game ($GameName + '_Data/Managed')
    New-Item -ItemType Directory -Path $managed -Force | Out-Null
    foreach ($name in @('ScriptsAssDef.dll', 'Kolkata.Speech.dll')) { Copy-Item -LiteralPath (Join-Path $managedSource $name) -Destination $managed }
    $runtimeSource = Get-RuntimeDir $GameRoot
    $runtime = Get-RuntimeDir $game
    New-Item -ItemType Directory -Path (Join-Path $runtime 'gpu') -Force | Out-Null
    $sourceManifest = Get-Content -LiteralPath (Join-Path $runtimeSource 'runtime-manifest.json') -Raw | ConvertFrom-Json
    foreach ($name in @('runtime-manifest.json') + @($sourceManifest.files | ForEach-Object { $_.path })) {
        $destination = Join-Path $runtime $name
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $runtimeSource $name) -Destination $destination
    }
    # An upgraded install keeps pristine worker/manifest copies; the fixture mirrors that layout.
    foreach ($name in @('QwenTtsWorker.exe.swyf.original', 'runtime-manifest.json.swyf.original')) {
        $source = Join-Path $runtimeSource $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $runtime $name) }
    }
    $manifestPath = Join-Path $runtime 'runtime-manifest.json'
    # A previously patched game keeps pristine copies as .swyf.original backups; a fresh install keeps live originals.
    $sourceManifestPath = Join-Path $runtimeSource 'runtime-manifest.json'
    $sourceWorkerPath = Join-Path $runtimeSource 'QwenTtsWorker.exe'
    $pristineManifest = Join-Path $runtimeSource 'runtime-manifest.json.swyf.original'
    $pristineWorker = $sourceWorkerPath + '.swyf.original'
    $originalManifestBytes = if (Test-Path -LiteralPath $pristineManifest) { [IO.File]::ReadAllBytes($pristineManifest) } else { [IO.File]::ReadAllBytes($sourceManifestPath) }
    $liveManifestBefore = (Get-FileHash -LiteralPath (Join-Path $runtimeSource 'runtime-manifest.json')).Hash
    function Assert-AllRuntimeChecksums([string]$label) {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.files) {
            Assert ((Get-FileHash -LiteralPath (Join-Path $runtime $entry.path)).Hash -eq $entry.sha256) "$label game manifest check: $($entry.path)"
        }
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
            if ($reference -eq 3 -and $startupBranch -and $LegacyPatched.ContainsKey($build.Original)) {
                $old = [byte[]]$plan.Output.Clone(); $old[$startupBranch] = 0x8F
                Assert ($LegacyPatched[$build.Original].ContainsKey((Sha256Hex $old))) 'Recognize v2.8 output hash'
                $states.Add(@{ Name = "v28-$backend"; Bytes = $old })
            }
        }
    }
    # Recreate exact released 2.9.6 variants, then exercise upgrade and restore through Get-Context.
    foreach ($previous in $build.PreviousPatches) {
        $oldPlan = Get-PatchPlan (Make-Context $original $build) $previous.Backend $previous.Reference
        $oldBytes = [byte[]]$oldPlan.Output.Clone()
        foreach ($edit in @($build.Edits | Where-Object { $_.QueueFirstAudio })) {
            CopyInto $oldBytes $edit.o (HexToBytes $edit.b)
        }
        Assert ((Sha256Hex $oldBytes) -eq $previous.Hash) 'Exact released 2.9.6 fixture'
        $states.Add(@{ Name = "v296-$($previous.Backend)-ref$($previous.Reference)"; Bytes = $oldBytes })
    }
    foreach ($state in $states) {
        [IO.File]::WriteAllBytes($dll, $state.Bytes)
        $ctx = Get-Context $game
        if ($state.Name -like 'v296-*') {
            Assert ($ctx.Already -and -not $ctx.Legacy) 'Released 2.9.6 recognized as a valid patch'
            $parts = $state.Name.Split('-')
            Assert ($ctx.CurVariant -eq $parts[1]) 'Upgrade detects previous backend'
            Assert ($ctx.ReferenceSeconds -eq [int]$parts[2].Substring(3)) 'Upgrade detects previous reference'
            $keep = Get-PatchPlan $ctx '' $ctx.ReferenceSeconds
            Assert ($keep.Backend -eq $ctx.CurVariant) 'Upgrade preserves backend'
        }
        foreach ($backend in @('auto', 'cpu', 'vulkan')) {
            foreach ($reference in @(3, 10)) {
                $plan = Get-PatchPlan $ctx $backend $reference
                Assert ((Sha256Hex $plan.Source) -eq $build.Original) "$($state.Name): exact original reconstruction"
                if ($startupBranch) { Assert ($plan.Output[$startupBranch] -eq 0xAC) "$($state.Name): valid startup branch" }
                Assert ($plan.Output[$referenceOffset] -eq $reference) "$($state.Name): reference selection"
            }
        }
    }
    if ($OldOriginal) {
        $oldBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $OldOriginal).Path)
        $oldBuild = @($Builds | Where-Object { $_.Original -eq (Sha256Hex $oldBytes) })
        if (-not $oldBuild) { throw 'Old original does not match any supported build.' }
        $oldBuild = $oldBuild[0]
        $oldVerify = @($oldBuild.Edits | Where-Object { $_.d -like 'Model verification*' } | Select-Object -First 1)
        $oldReferenceOffset = (@($oldBuild.Edits | Where-Object { $_.Reference })[0]).o
        foreach ($backend in @('auto', 'cpu', 'vulkan')) {
            foreach ($reference in @(3, 10)) {
                $plan = Get-PatchPlan (Make-Context $oldBytes $oldBuild) $backend $reference
                Assert ((Sha256Hex $plan.Source) -eq $oldBuild.Original) "Old $($oldBuild.Tag) original reconstruction"
                if ($oldVerify) { Assert ($plan.Output[$oldVerify.o + 3] -eq 0xAC) "Old $($oldBuild.Tag) startup branch corrected" }
                Assert ($plan.Output[$oldReferenceOffset] -eq $reference) "Old $($oldBuild.Tag) reference selection"
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
    Assert-AllRuntimeChecksums 'After installation'
    Assert ((Get-FileHash -LiteralPath ($manifestPath + '.swyf.original')).Hash -eq $RuntimeSpec.OriginalManifest) 'Original manifest backup verified'
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
    Assert-AllRuntimeChecksums 'After restore'
    Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $RuntimeSpec.OriginalManifest) 'Restore recovers byte-identical original manifest'
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Restore also restores original worker'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Restore ignores stale backup and restores exact original'
    foreach ($state in @($states | Where-Object { $_.Name -like 'v296-*' })) {
        [IO.File]::WriteAllBytes($dll, $state.Bytes)
        Set-RuntimePlan (Get-RuntimePlan $game)
        $previousBackend = (Get-Context $game).CurVariant
        Invoke-MenuAction $game '2'
        Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Patched[$previousBackend]) 'Menu 2 upgrades an installed 2.9.6 variant with the same backend'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.PatchedWorker) 'Upgrade preserves current worker'
        Invoke-Restore (Get-Context $game)
        Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Upgraded 2.9.7 restores original DLL'
        Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $RuntimeSpec.OriginalManifest) 'Upgraded 2.9.7 restores original manifest'
        [IO.File]::WriteAllBytes($dll, $state.Bytes)
        Invoke-Restore (Get-Context $game)
        Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) '2.9.6 can also be restored directly'
    }
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
    Assert ($dispatches[-1].Action -eq 'logs' -and $dispatches.Count -eq 7) 'Collecting logs neither launches nor patches the game'
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
    $originalWorkerBytes = if (Test-Path -LiteralPath $pristineWorker) { [IO.File]::ReadAllBytes($pristineWorker) } else { [IO.File]::ReadAllBytes($workerPath) }
    [IO.File]::WriteAllText($workerPath, 'unknown worker')
    Assert-Throws { Get-RuntimePlan $game } 'Unknown worker preserved'
    Assert ([IO.File]::ReadAllText($workerPath) -eq 'unknown worker') 'Worker validation has no side effects'
    [IO.File]::WriteAllBytes($workerPath, $originalWorkerBytes)

    # Reproduce the real Windows failure: our worker + the unchanged upstream manifest.
    $payloadBytes = [IO.File]::ReadAllBytes((Join-Path $PatcherRoot 'payload/QwenTtsWorker.exe'))
    [IO.File]::WriteAllBytes($workerPath, $payloadBytes)
    [IO.File]::WriteAllBytes($manifestPath, $originalManifestBytes)
    Assert-Throws { Assert-RuntimeManifestReady $game } 'Regression: mismatched manifest cannot silently launch MOSS'
    $repair = Get-RuntimePlan $game
    Assert ($repair.CurHash -eq $repair.Hash -and $repair.Manifest.CurHash -ne $repair.Manifest.Hash) 'Same worker still requires a manifest repair'
    Set-RuntimePlan $repair
    Assert-RuntimeManifestReady $game
    Assert-AllRuntimeChecksums 'After repairing the reported failure'
    $repairedManifestHash = (Get-FileHash -LiteralPath $manifestPath).Hash
    Set-RuntimePlan (Get-RuntimePlan $game)
    Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $repairedManifestHash) 'Repeated repair is idempotent'
    Invoke-Restore (Get-Context $game)
    Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $RuntimeSpec.OriginalManifest) 'Restore repairs runtime even with an original game DLL'

    $foreignManifest = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($originalManifestBytes).Replace('concrt140.dll', 'foreign.dll'))
    [IO.File]::WriteAllBytes($manifestPath, $foreignManifest)
    Assert-Throws { Invoke-Patch (Get-Context $game) 'cpu' 10 } 'Unrelated manifest edits rejected before applying any patch'
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Unknown manifest leaves original worker unchanged'
    Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $build.Original) 'Unknown manifest leaves game DLL unchanged'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifestBytes)
    $manifestBackup = $manifestPath + '.swyf.original'
    [IO.File]::WriteAllText($manifestBackup, 'foreign backup')
    Assert-Throws { Get-RuntimePlan $game } 'Unknown manifest backup is not overwritten'
    Assert ([IO.File]::ReadAllText($manifestBackup) -eq 'foreign backup') 'Unknown backup preserved'
    [IO.File]::WriteAllBytes($manifestBackup, $originalManifestBytes)
    $repair = Get-RuntimePlan $game
    [IO.File]::WriteAllBytes($manifestPath, $foreignManifest)
    Assert-Throws { Set-RuntimePlan $repair } 'Concurrent manifest change detected before worker mutation'
    Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Concurrent manifest rejection preserves worker'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifestBytes)

    $auxiliaryPath = Join-Path $runtime 'concrt140.dll'
    $auxiliaryBytes = [IO.File]::ReadAllBytes($auxiliaryPath)
    [IO.File]::WriteAllText($auxiliaryPath, 'corrupt dependency outside the four ABI checks')
    Assert-Throws { Get-RuntimePlan $game } 'Every manifest dependency is validated, including CRT files'
    [IO.File]::WriteAllBytes($auxiliaryPath, $auxiliaryBytes)
    $realReplaceVerified = ${function:ReplaceVerified}
    try {
        $script:failurePath = $manifestPath
        function ReplaceVerified([string]$path, [byte[]]$current, [byte[]]$next, [string]$expectedHash) {
            if ($path -eq $script:failurePath) { throw 'Simulated manifest/DLL write failure' }
            & $realReplaceVerified $path $current $next $expectedHash
        }
        Assert-Throws { Set-RuntimePlan (Get-RuntimePlan $game) } 'Manifest write failure aborts installation'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Manifest failure rolls back the already-written worker'
        Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $RuntimeSpec.OriginalManifest) 'Failed manifest remains original'
        $script:failurePath = $dll
        Assert-Throws { Invoke-Patch (Get-Context $game) 'cpu' 10 } 'Game DLL failure aborts outer transaction'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Outer failure rolls back worker'
        Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $RuntimeSpec.OriginalManifest) 'Outer failure rolls back manifest'
        $script:failurePath = ''
        Invoke-Patch (Get-Context $game) 'cpu' 10
        $installedDllHash = (Get-FileHash -LiteralPath $dll).Hash
        $script:failurePath = $dll
        Assert-Throws { Invoke-Restore (Get-Context $game) } 'Game DLL restore failure is reported'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.PatchedWorker) 'Failed restore keeps installed worker'
        Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq $repairedManifestHash) 'Failed restore keeps matching installed manifest'
        Assert ((Get-FileHash -LiteralPath $dll).Hash -eq $installedDllHash) 'Failed restore keeps installed game DLL'
    } finally { Set-Item -Path Function:ReplaceVerified -Value $realReplaceVerified }
    Invoke-Restore (Get-Context $game)
    try {
        function ReplaceVerified([string]$path, [byte[]]$current, [byte[]]$next, [string]$expectedHash) {
            if ($path -eq $manifestPath) { [IO.File]::WriteAllBytes($manifestPath, $foreignManifest) }
            & $realReplaceVerified $path $current $next $expectedHash
        }
        Assert-Throws { Set-RuntimePlan (Get-RuntimePlan $game) } 'Concurrent manifest write during installation aborts transaction'
        Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -eq (Sha256Hex $foreignManifest)) 'Rollback preserves concurrent foreign manifest'
        Assert ((Get-FileHash -LiteralPath $workerPath).Hash -eq $RuntimeSpec.OriginalWorker) 'Concurrent manifest failure restores our worker mutation'
    } finally {
        Set-Item -Path Function:ReplaceVerified -Value $realReplaceVerified
        [IO.File]::WriteAllBytes($manifestPath, $originalManifestBytes)
    }
    Write-Host 'PASS: manifest regression, exact runtime verification, repair, rollback and concurrency.' 

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
        # A fully installed prior release has its own matching manifest (2.9.1).
        $previousManifest = Get-RuntimeManifestPlan $runtime $previousHash
        [IO.File]::WriteAllBytes($manifestPath, $previousManifest.Output)
        $runtimePlan = Get-RuntimePlan $game
        Set-RuntimePlan $runtimePlan
        Assert-AllRuntimeChecksums 'Previous release upgrade'
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

    # Exercise automatic repair through the real menu action, not just the model helpers.
    $codecPath = Join-Path $cache $ModelSpecs.codec.Name
    $originalQ8Path = Join-Path $cache 'qwen-talker-0.6b-base-Q8_0.original.gguf'
    Remove-Item -LiteralPath $originalQ8Path
    [IO.File]::WriteAllBytes($active, (New-Object byte[] 17757))
    [IO.File]::WriteAllBytes($codecPath, (New-Object byte[] 17770))
    $badActiveHash = Get-ModelHash $active; $badCodecHash = Get-ModelHash $codecPath
    $beforeDll = Get-ModelHash $dll; $beforeWorker = Get-ModelHash $workerPath; $beforeManifest = Get-ModelHash $manifestPath
    Assert-Throws { Invoke-MenuAction $game '2' } 'Apply aborts before game changes when automatic model download fails'
    Assert ((Get-ModelHash $dll) -eq $beforeDll -and (Get-ModelHash $workerPath) -eq $beforeWorker -and (Get-ModelHash $manifestPath) -eq $beforeManifest) 'Download failure leaves DLL, worker and manifest unchanged'
    Assert ((Get-ModelHash $active) -eq $badActiveHash -and (Get-ModelHash $codecPath) -eq $badCodecHash) 'Download failure leaves both live model files unchanged'
    $script:repairDownloads = 0
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
        $script:repairDownloads++
        $kind = @('q8', 'q4', 'codec') | Where-Object { $Uri.EndsWith('/' + $ModelSpecs[$_].Name) } | Select-Object -First 1
        if (-not $kind) { throw 'Unexpected download URL' }
        $text = "fixture-$kind" + $(if ($kind -eq 'q8') { '-original' })
        [IO.File]::WriteAllText($OutFile, $text)
    }
    $realModelInstall = ${function:Install-ModelOperation}
    try {
        function Install-ModelOperation($operation) {
            if ($operation.Path -eq $active) { throw 'Simulated model install failure after codec replacement' }
            & $realModelInstall $operation
        }
        Assert-Throws { Invoke-MenuAction $game '2' } 'Model install failure aborts the full patch transaction'
        Assert ((Get-ModelHash $dll) -eq $beforeDll -and (Get-ModelHash $workerPath) -eq $beforeWorker -and (Get-ModelHash $manifestPath) -eq $beforeManifest) 'Model commit failure rolls back DLL, worker and manifest'
        Assert ((Get-ModelHash $active) -eq $badActiveHash -and (Get-ModelHash $codecPath) -eq $badCodecHash) 'Model commit failure rolls back repaired codec too'
    } finally { Set-Item Function:Install-ModelOperation $realModelInstall }
    $script:repairDownloads = 0
    Invoke-MenuAction $game '2'
    Assert ($script:repairDownloads -eq 2) 'Apply automatically downloads both corrupt model files'
    Assert ((Test-ModelFile $active $ModelSpecs.q8) -and (Test-ModelFile $codecPath $ModelSpecs.codec)) 'Apply installs verified talker and codec'
    Assert ((Get-Context $game).Already) 'Apply also installs game patch'
    Assert-AllRuntimeChecksums 'Automatic model repair'
    $backups = @(Get-ChildItem -LiteralPath $cache -Filter '*.swyf-before-repair-*' -File)
    Assert (@($backups | Where-Object { (Get-ModelHash $_.FullName) -eq $badActiveHash }).Count -eq 1) 'Broken talker preserved after successful apply'
    Assert (@($backups | Where-Object { (Get-ModelHash $_.FullName) -eq $badCodecHash }).Count -eq 1) 'Broken codec preserved after successful apply'
    Invoke-MenuAction $game '2'
    Assert ($script:repairDownloads -eq 2) 'Reapplying healthy patch does not redownload models'
    Assert (@(Get-ChildItem -LiteralPath $cache -Force | Where-Object { $_.Name -like '*.tmp' }).Count -eq 0) 'No staging folders left after apply success/failure'
    Invoke-Restore (Get-Context $game)
    Write-Host 'PASS: automatic model repair via menu option 2 and full transaction rollback.'


    $script:PatcherRoot = Join-Path $testRoot 'patcher'
    $logFolder = New-DiagnosticFolder 'test'
    [IO.File]::WriteAllText((Join-Path $logFolder 'Player.log'), "[SpeechRequest] provider=qwen stage=first_audio`n[SpeechRequest] provider=qwen stage=completed succeeded=True firstAudio=True cancelled=False`n[SpeechRequest] provider=qwen stage=completed succeeded=False firstAudio=True cancelled=True`n[Speech] No audio progress.`nException=none`nInvalidOperationException: current failure`n")
    foreach ($name in @('before-Player.log', 'after-Player.log', 'Player-prev.log')) {
        [IO.File]::WriteAllText((Join-Path $logFolder $name), "NullReferenceException: old startup crash`n[SpeechRequest] provider=qwen stage=completed succeeded=False cancelled=False`n")
    }
    New-Item -ItemType Directory -Path (Join-Path $logFolder 'qwen-worker') | Out-Null
    [IO.File]::WriteAllText((Join-Path $logFolder 'qwen-worker/qwen-current.log'), "LOAD requestedBackend=Vulkan0 q4GpuCompatibility=True`nPROFILE GGML_VK_DISABLE_F16=1`nGPU_CANDIDATE backend=Vulkan0 type=integrated name=Intel Iris Xe`nGPU_SELECTED backend=Vulkan1 type=discrete name=NVIDIA RTX 3050 Laptop`n[Perf] Total 14709.6 ms (110 frames, audio 8.80 s, RTF 1.672)`nCOMPLETE request=1`n")
    Write-DiagnosticReport $game $logFolder
    Complete-Diagnostics $logFolder
    Assert (Test-Path -LiteralPath ($logFolder + '.zip')) 'Diagnostic ZIP created'
    $summary = Get-Content -LiteralPath (Join-Path $logFolder 'speech-summary.txt') -Raw
    Assert ($summary -match 'CURRENT QWEN WORKER' -and $summary -match 'q4GpuCompatibility=True') 'Current native worker profile included in summary'
    Assert ($summary -match 'GPU_SELECTED backend=Vulkan1 type=discrete name=NVIDIA RTX 3050 Laptop') 'Summary includes actual selected synthesis device'
    Assert ($summary -match 'GPU_CANDIDATE backend=Vulkan0 type=integrated' -and $summary -match 'RTF 1.672') 'Summary retains integrated adapter and realtime performance evidence'
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
    [IO.File]::WriteAllText((Join-Path $logFolder 'Player.log'), "[Qwen3 TTS] Worker stopped; using existing speech for this session. Qwen runtime checksum mismatch: QwenTtsWorker.exe`n[SpeechRequest] provider=moss stage=first_audio`n[SpeechRequest] provider=moss stage=completed succeeded=True cancelled=False`n[CallTrace] stage=ONLINE_AI_PRIMARY_RAW fallback=True error=cancelled`n")
    Write-SpeechSummary $logFolder
    $summary = Get-Content -LiteralPath (Join-Path $logFolder 'speech-summary.txt') -Raw
    Assert ($summary -match 'ACTUAL SPEECH: MOSS only' -and $summary -match 'QWEN DISABLED DURING THIS RUN') 'Reported user failure explicitly identifies MOSS and disabled Qwen'
    Assert ($summary -match 'Qwen runtime checksum mismatch: QwenTtsWorker.exe') 'Qwen disable reason retained'
    Assert ($summary -match 'MOSS requests: succeeded=1; cancelled=0; failed=0; first_audio=1') 'MOSS results counted separately'
    Assert ($summary -match 'Online dialogue fallbacks: 1') 'Dialogue cancellation not mislabelled as TTS failure'
    Remove-Item -LiteralPath (Join-Path $logFolder 'Player.log')
    Write-SpeechSummary $logFolder
    $summary = Get-Content -LiteralPath (Join-Path $logFolder 'speech-summary.txt') -Raw
    Assert ($summary -match 'Player.log is missing' -and $summary -notmatch 'NullReferenceException|Qwen requests:') 'Missing current log never substitutes stale results'
    # Normal launches export recent automatic sessions without launching the game.
    $autoRoot = Join-Path $testProfile 'swyf-qwen-logs'
    for ($i = 1; $i -le 4; $i++) {
        $name = 'session-20261024-00000' + $i + '-000-' + ('b' * 32)
        $sessionFolder = Join-Path $autoRoot $name
        New-Item -ItemType Directory -Path $sessionFolder -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $sessionFolder 'session.log'), "WORKER automatic $i`nCOMPLETE request=1")
        [IO.File]::WriteAllBytes((Join-Path $sessionFolder 'audio-123-0001.wav'), [byte[]]@(82,73,70,70))
        [IO.File]::WriteAllText((Join-Path $sessionFolder 'unrelated-secret.txt'), 'do not export')
    }
    [IO.File]::WriteAllText((Join-Path $testProfile 'Player.log'), '[SpeechRequest] provider=moss stage=first_audio')
    $export = New-DiagnosticFolder 'normal'
    Copy-PlayerLogs $export ''
    Copy-RecentWorkerLogs $export
    Write-SpeechSummary $export
    $recentRoot = Join-Path $export 'recent-qwen-worker'
    Assert (@(Get-ChildItem -LiteralPath $recentRoot -Directory).Count -eq 3) 'Normal export collects three recent worker sessions'
    Assert (@(Get-ChildItem -LiteralPath $recentRoot -Filter '*.wav' -File -Recurse).Count -eq 3) 'Normal export includes automatic audio'
    Assert (@(Get-ChildItem -LiteralPath $recentRoot -Filter '*secret*' -File -Recurse).Count -eq 0) 'Export excludes unrelated session files'
    $summary = [IO.File]::ReadAllText((Join-Path $export 'speech-summary.txt'))
    Assert ($summary -match 'RECENT AUTOMATIC WORKER SESSIONS' -and $summary -match 'WORKER automatic 4') 'Automatic worker evidence included with historical warning'
    Assert ($summary -match 'ACTUAL SPEECH: MOSS only' -and $summary -notmatch 'WORKER automatic 1') 'Recent worker evidence cannot mask current MOSS fallback; oldest session excluded'
    Complete-Diagnostics $export
    Assert (Test-Path -LiteralPath ($export + '.zip')) 'Normal-launch diagnostics packaged without launching a process'
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
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtimeSource 'runtime-manifest.json')).Hash -eq $liveManifestBefore) 'User game manifest unchanged throughout tests'
    Assert ((Get-FileHash -LiteralPath (Join-Path $runtimeSource 'QwenTtsWorker.exe')).Hash -eq $liveWorkerBefore) 'User game worker unchanged throughout tests'
    Assert ((Get-FileHash -LiteralPath (Join-Path $managedSource 'Assembly-CSharp.dll')).Hash -eq $liveBefore) 'User game DLL unchanged throughout tests'
    Write-Host "PASS: $checks assertions. All mutable fixtures were under $testRoot"
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
