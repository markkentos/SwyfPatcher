# SwyfPatcher - universal Qwen3 TTS patch for "Scam With Your Friends"
# Enables the local Qwen3 neural TTS on modest hardware, lets you switch
# the inference backend (Vulkan / CPU) and swap the talker model (Q4_K_M / Q8_0).
#
# Original fix: psihozniy (hardware-eligibility + timeout patch, v2.1 lineage).
# Adapted, rewritten as a dependency-free PowerShell tool and maintained by markkentos.
# Some ideas (model switching, Steam libraryfolders.vdf discovery, interactive hints)
# borrowed from the community SwyfPatcher-2.6.0 fork.
#
# Usage:  SwyfPatch.bat [--backend auto|cpu|vulkan] [--model q4|q8] [--check | --restore] [game-folder]

param(
    [string]$Backend = 'auto',
    [string]$Model = '',
    [switch]$Check,
    [switch]$Restore,
    [string]$GamePath = ''
)

$ErrorActionPreference = 'Stop'
$Version = '2.7'
$GameName = 'Scam With Your Friends'
$Code = 0

function HexToBytes([string]$s) {
    $n = [int]($s.Length / 2)
    $r = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) { $r[$i] = [Convert]::ToByte($s.Substring($i * 2, 2), 16) }
    $r
}
function Sha256Hex([byte[]]$b) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($b)) -replace '-', '') } finally { $sha.Dispose() }
}
function MatchesAt([byte[]]$d, [int]$off, [byte[]]$p) {
    if ($off -lt 0 -or ($off + $p.Length) -gt $d.Length) { return $false }
    for ($i = 0; $i -lt $p.Length; $i++) { if ($d[$off + $i] -ne $p[$i]) { return $false } }
    $true
}
function CopyInto([byte[]]$d, [int]$off, [byte[]]$s) { for ($i = 0; $i -lt $s.Length; $i++) { $d[$off + $i] = $s[$i] } }
function Get-ExistingBackup([string]$dllPath) {
    foreach ($s in @('.swyf.original', '.swyf-v23.original', '.swyf-v22.original')) {
        $p = $dllPath + $s
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}
function ReplaceVerified([string]$dllPath, [byte[]]$expectedCurrent, [byte[]]$next, [string]$hash) {
    $tmp = "$dllPath.swyf-$PID.tmp"
    try {
        [IO.File]::WriteAllBytes($tmp, $next)
        if ((Sha256Hex ([IO.File]::ReadAllBytes($tmp))) -ne $hash) { throw 'Temporary file verification failed.' }
        if ((Sha256Hex ([IO.File]::ReadAllBytes($dllPath))) -ne (Sha256Hex $expectedCurrent)) { throw 'DLL changed during patching. No replacement performed.' }
        [IO.File]::Replace($tmp, $dllPath, [NullString]::Value)
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

# Patched HardwareEligible bodies (141 bytes each; ldstr tokens differ per build, shape identical):
#   auto:   VRAM>=1024 -> out="Vulkan0" else out="CPU"; always return true
#   cpu:    out="CPU" unconditionally; return true
#   vulkan: out="Vulkan0" unconditionally; return true
$AfterA   = '0E052000040000320A0E087296E30370512B080E08728EE3037051' + ('00' * 112) + '172A'
$CpuA     = '0E08728EE3037051' + ('00' * 131) + '172A'
$VulkanA  = '0E087296E3037051' + ('00' * 131) + '172A'
$AfterB   = '0E052000040000320A0E087294C40770512B080E08728CC4077051' + ('00' * 112) + '172A'
$ModelVerifyA = ('170BDD8F000000' + ('00' * 22))

$Builds = @(
    @{
        Tag      = '2026-10-24'
        Original = '978FD1B5C50F28B523BA49145A9F716A3C2C9CB3DED20BBB175976116AD2020E'
        Patched  = @{
            auto   = '2834A771E05B3CD7A7104D37267E8A106C09D28C8BA3A84733396E145D9A6582'
            cpu    = '60404F5A5912533A26A3BB43B69C8FC0601C23FD1CF7FF5ADA01550B2733DB85'
            vulkan = 'B25FC6A03702C043DCD54DE20EDEAD809E3C4D74A6D27090230E2E5834A510CB'
        }
        Scripts  = '07E6BF770800EE75DDC3C5953232FE2CBBB2E85DD9933C0231092E0F3DB43403'
        Speech   = '737E28564E6BE0F5D5CE28D679AF78B2D616FBF5591225E5E83EA0A26945D66D'
        HwOffset = 0x8BEAC
        HwBefore = '0E05200016000032500E0620DE1000002E090E062002100000333E0E062002100000331B0E07209F6900002E2C0E0720DF6700002E230E07204C7400002E1A0E0620DE100000330E0E0720852B0000FE0116FE012B04172B01160A0E08062D07728EE303702B057296E303705102065F2C190320983A000032110420001800006A3208051AFE0416FE012A162A'
        Blocks   = @{ auto = $AfterA; cpu = $CpuA; vulkan = $VulkanA }
        Edits    = @(
            @{ o = 0x8B29C; b = '0000000000003E40'; a = '0000000000C07240'; d = 'Prompt cancellation: 30 -> 300 seconds' },
            @{ o = 0x8B303; b = '0000000000003440'; a = '0000000000C07240'; d = 'First audio deadline: 20 -> 300 seconds' },
            @{ o = 0x8BA06; b = '0A'; a = '03'; d = 'Voice reference: 10 -> 3 seconds' },
            @{ o = 0x8BC58; b = '0000000000003E40'; a = '0000000000005E40'; d = 'Chunk timeout: 30 -> 120 seconds' },
            @{ o = 0x8BD54; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare timeout: 20 -> 120 seconds' },
            @{ o = 0x8BDE3; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare deadline: 20 -> 120 seconds' },
            @{ o = 0x8AF8C; b = '087B9C13000473C302000A28C402000A087B9E1300047BC51300042E07'; a = $ModelVerifyA; d = 'Model verification: allow custom quantizations (Q4_K_M)' }
        )
    },
    @{
        Tag      = '2026-10-22'
        Original = 'F94B92369D2AC0F7C1F10A30AE6A1C7FC4CEE99C538693C162B1A7FDC02A2BB2'
        Patched  = @{
            auto   = 'C162A0AADA0D1E7799D3669EAE0BF5D40098724A13BAF964DD2E11C9807B5497'
            cpu    = 'DC3868A57F0D6903E1FADB2FF9E43B72EBB382567D2B6A3C3AF1D3182D076CD5'
            vulkan = '6A4F244651D9FD4774535BB5419E1B3BB6B600DFDE3427F4D5AEFB10FE2D51C0'
        }
        Scripts  = '5432D089E0E9C93B1A74ADDAF27EC240758FC2A183EC913CA41D9949C46E0A84'
        Speech   = '7F5A3EC065E87D85705F14B36E490E7BF2B0A1C95300813E7D9D197836BECF6B'
        HwOffset = 0x1222CC
        HwBefore = '0E05200016000032500E0620DE1000002E090E062002100000333E0E062002100000331B0E07209F6900002E2C0E0720DF6700002E230E07204C7400002E1A0E0620DE100000330E0E0720852B0000FE0116FE012B04172B01160A0E08062D077261DA07702B057269DA07705102065F2C190320983A000032110420001800006A3208051AFE0416FE012A162A'
        Blocks   = @{ auto = $AfterB; cpu = $CpuA; vulkan = $VulkanA }
        Edits    = @(
            @{ o = 0x1216BC; b = '0000000000003E40'; a = '0000000000C07240'; d = 'Prompt cancellation: 30 -> 300 seconds' },
            @{ o = 0x121723; b = '0000000000003440'; a = '0000000000C07240'; d = 'First audio deadline: 20 -> 300 seconds' },
            @{ o = 0x121E26; b = '0A'; a = '03'; d = 'Voice reference: 10 -> 3 seconds' },
            @{ o = 0x122078; b = '0000000000003E40'; a = '0000000000005E40'; d = 'Chunk timeout: 30 -> 120 seconds' },
            @{ o = 0x122174; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare timeout: 20 -> 120 seconds' },
            @{ o = 0x122203; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare deadline: 20 -> 120 seconds' },
            @{ o = 0x1213AC; b = '087B9A27000473C302000A28C402000A087B9C2700047BC32700042E07'; a = $ModelVerifyA; d = 'Model verification: allow custom quantizations (Q4_K_M)' }
        )
    },
    @{
        Tag      = '2026-10-19'
        Original = '1848CE450AB489B14539A2B2B0C995599965DDE03A61479A15772DDF17C24025'
        Patched  = @{ auto = 'A09AB9C67B229007199D6202E8DE11CE1E0B0A4F4785E66317A8FAC4FB98FB7A' }
        Scripts  = '0125EA190318ED20B09041EEF0303BA3A73355D6073DAB131C2234BCD471FEFC'
        Speech   = $null
        HwOffset = 0x11E638
        HwBefore = '0E0520001E000032500E0620DE1000002E090E062002100000333E0E062002100000331B0E07209F6900002E2C0E0720DF6700002E230E07204C7400002E1A0E0620DE100000330E0E0720852B0000FE0116FE012B04172B01160A0E08062D07728CC407702B057294C407705102065F2C190320983A000032110420001800006A3208051AFE0416FE012A162A'
        Blocks   = @{ auto = $AfterB }
        Edits    = @(
            @{ o = 0x11DA28; b = '0000000000003E40'; a = '0000000000C07240'; d = 'Prompt cancellation: 30 -> 300 seconds' },
            @{ o = 0x11DA8F; b = '0000000000003440'; a = '0000000000C07240'; d = 'First audio deadline: 20 -> 300 seconds' },
            @{ o = 0x11E4E0; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare timeout: 20 -> 120 seconds' },
            @{ o = 0x11E56F; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare timeout: 20 -> 120 seconds' },
            @{ o = 0x11E3E4; b = '0000000000003E40'; a = '0000000000005E40'; d = 'Chunk timeout: 30 -> 120 seconds' },
            @{ o = 0x11E192; b = '0A'; a = '03'; d = 'Voice reference: 10 -> 3 seconds' }
        )
    }
)

# Legacy (pre-2.7) patched states of build 2026-10-22 without the model-verify edit.
# They are recognized and silently upgraded to the v2.7 variant on the next patch run.
$LegacyPatched = @{
    'F94B92369D2AC0F7C1F10A30AE6A1C7FC4CEE99C538693C162B1A7FDC02A2BB2' = @{
        '7FB0CD47103813A740E5CF5755055DFC11AF3E2F3A8F4F0F14296121C90C27B3' = 'auto'
        '39D7DFE1D3A9E9E1376AAC1C3090393ED5B841F4CBC4D1C4E8006436F8A6893A' = 'cpu'
        '7308A9DC6EE1983A622C77270D0817A91AE4CCD53F9649E145B539D74CD47290' = 'vulkan'
    }
}

try {
    # ---------- normalize arguments ----------
    $Backend = $Backend.ToLowerInvariant()
    if ($Backend -notin @('auto', 'cpu', 'vulkan')) { throw "Invalid --backend value: $Backend (use auto, cpu or vulkan)." }
    $action = 'patch'
    if ($Restore) { $action = 'restore' }
    elseif ($Check) { $action = 'check' }
    $Model = $Model.ToLowerInvariant()
    if ($Model -and $Model -notin @('q4', 'q8')) { throw "Invalid --model value: $Model (use q4 or q8)." }

    # ---------- locate the game ----------
    if ($GamePath) {
        if (-not (Test-Path -LiteralPath $GamePath)) { throw "Game folder not found: $GamePath" }
        $game = (Resolve-Path -LiteralPath $GamePath).Path
    } else {
        $dirs = New-Object 'System.Collections.Generic.HashSet[string]'
        # 1) Steam libraries from registry + libraryfolders.vdf (idea borrowed from the 2.6.0 fork)
        $steamRoots = @()
        $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($sp) { $steamRoots += $sp }
        if (Test-Path 'C:\Program Files (x86)\Steam') { $steamRoots += 'C:\Program Files (x86)\Steam' }
        foreach ($root in $steamRoots) {
            $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                    [void]$dirs.Add(($m.Groups[1].Value -replace '\\\\', '\'))
                }
            }
            [void]$dirs.Add($root)
        }
        # 2) fallback: fixed layouts on every fixed drive
        foreach ($drv in [IO.DriveInfo]::GetDrives()) {
            if (-not $drv.IsReady) { continue }
            foreach ($rel in @('SteamLibrary\steamapps\common', 'Program Files (x86)\Steam\steamapps\common', 'Steam\steamapps\common', 'Program Files (x86)\steamapps\common')) {
                [void]$dirs.Add((Join-Path (Join-Path $drv.RootDirectory.FullName $rel) ''))
            }
        }
        $found = New-Object 'System.Collections.Generic.List[string]'
        foreach ($d in $dirs) {
            $p = Join-Path $d $GameName
            if (Test-Path -LiteralPath (Join-Path $p ($GameName + '_Data\Managed\Assembly-CSharp.dll'))) { $found.Add((Resolve-Path -LiteralPath $p).Path) }
        }
        if ($found.Count -gt 1) {
            throw ("Several game folders found:`n" + (($found | ForEach-Object { '  ' + $_ }) -join "`n") + "`nDrag the correct folder onto SwyfPatch.bat.")
        }
        if ($found.Count -eq 0) { throw 'Game not found. Drag the game folder onto SwyfPatch.bat.' }
        $game = $found[0]
    }
    Write-Host "Game: $game"

    $managed = Join-Path $game ($GameName + '_Data\Managed')
    $dll = Join-Path $managed 'Assembly-CSharp.dll'
    $scripts = Join-Path $managed 'ScriptsAssDef.dll'
    $speech = Join-Path $managed 'Kolkata.Speech.dll'
    if (-not (Test-Path -LiteralPath $dll)) { throw 'Assembly-CSharp.dll not found. Point me at the game root folder.' }
    if (-not (Test-Path -LiteralPath $scripts)) { throw 'ScriptsAssDef.dll not found. Verify files in Steam. No changes made.' }

    # ---------- identify build and current state ----------
    $current = [IO.File]::ReadAllBytes($dll)
    $curHash = Sha256Hex $current
    $build = $null
    $already = $false
    $curVariant = $null
    $legacy = $false
    foreach ($b in $Builds) {
        if ($curHash -eq $b.Original) { $build = $b; break }
        foreach ($v in @('auto', 'cpu', 'vulkan')) {
            if ($b.Patched[$v] -and $curHash -eq $b.Patched[$v]) { $build = $b; $already = $true; $curVariant = $v; break }
        }
        if (-not $build -and $LegacyPatched.ContainsKey($b.Original)) {
            foreach ($h in $LegacyPatched[$b.Original].Keys) {
                if ($curHash -eq $h) { $build = $b; $already = $true; $curVariant = $LegacyPatched[$b.Original][$h]; $legacy = $true; break }
            }
        }
        if ($build) { break }
    }
    if ($null -eq $build) {
        throw ("Unsupported Assembly-CSharp.dll (SHA-256 $curHash).`nSteam likely updated the game. Verify files in Steam; this patcher needs an adaptation for the new build. No changes made.")
    }
    if (-not $build.Patched[$Backend] -or -not $build.Blocks[$Backend]) {
        throw ("--backend $Backend is not supported for build $($build.Tag). Use --backend auto. No changes made.")
    }
    $state = 'original'
    if ($already) {
        $state = "PATCHED (backend: $curVariant$(if ($legacy) { ', legacy layout' }))".Replace('  ', ' ')
    }
    Write-Host ("SwyfPatcher v$Version. Build: " + $build.Tag + " (state: $state)")

    if ((Sha256Hex ([IO.File]::ReadAllBytes($scripts))) -ne $build.Scripts) { throw 'Unsupported ScriptsAssDef.dll. Verify files in Steam. No changes made.' }
    if ($build.Speech) {
        if (-not (Test-Path -LiteralPath $speech)) { throw 'Kolkata.Speech.dll is missing. Verify files in Steam. No changes made.' }
        if ((Sha256Hex ([IO.File]::ReadAllBytes($speech))) -ne $build.Speech) { throw 'Unsupported Kolkata.Speech.dll. Verify files in Steam. No changes made.' }
    }
    Write-Host '[OK] All game DLL hashes match a supported build.'

    if ($action -ne 'check' -or $Model) {
        $procs = @()
        $procs += Get-Process -Name $GameName -ErrorAction SilentlyContinue
        $procs += Get-Process -Name 'QwenTtsWorker' -ErrorAction SilentlyContinue
        if ($procs) { throw 'Close the game first (Scam With Your Friends / QwenTtsWorker are running). No changes made.' }
    }

    # ---------- model switch (--model q4|q8), independent of DLL patching ----------
    if ($Model) {
        $base = Join-Path $env:USERPROFILE 'AppData\LocalLow\Jatater Worldwide\Scam With Your Friends\qwen3-tts'
        $sub = Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $sub) { throw "Qwen model cache not found under $base. Launch the game once so it downloads the models." }
        $mdir = $sub.FullName
        $active = Join-Path $mdir 'qwen-talker-0.6b-base-Q8_0.gguf'
        $orig = Join-Path $mdir 'qwen-talker-0.6b-base-Q8_0.original.gguf'
        $q4 = Join-Path $mdir 'qwen-talker-0.6b-base-Q4_K_M.gguf'
        if (-not (Test-Path -LiteralPath $active)) { throw "Active talker model not found: $active" }
        $activeMb = [math]::Round((Get-Item -LiteralPath $active).Length / 1MB)
        $activeKind = if ($activeMb -lt 700) { 'q4' } else { 'q8' }
        Write-Host ("Current talker model: $activeKind (~$activeMb MB)")

        if ($Model -eq $activeKind) {
            Write-Host "[OK] Model $Model is already active. Nothing to do."
        } elseif ($Model -eq 'q4') {
            if (-not (Test-Path -LiteralPath $q4)) {
                # seed from the pre-built local copy, then fall back to mirrors
                $seed = 'D:\Temp\swyf-quant\qwen-talker-q4km-final.gguf'
                if (Test-Path -LiteralPath $seed) {
                    Copy-Item -LiteralPath $seed -Destination $q4 -Force
                    Write-Host "[OK] Seeded Q4_K_M from local pre-built copy ($seed)"
                } else {
                    $mirrors = @(
                        'https://hf.aihoster.ru/Serveurperso/Qwen3-TTS-GGUF/resolve/main/qwen-talker-0.6b-base-Q4_K_M.gguf',
                        'https://huggingface.co/Serveurperso/Qwen3-TTS-GGUF/resolve/main/qwen-talker-0.6b-base-Q4_K_M.gguf',
                        'https://hf-mirror.com/Serveurperso/Qwen3-TTS-GGUF/resolve/main/qwen-talker-0.6b-base-Q4_K_M.gguf'
                    )
                    $ok = $false
                    foreach ($u in $mirrors) {
                        try {
                            Write-Host "[INFO] Downloading Q4_K_M from $u"
                            Invoke-WebRequest -Uri $u -OutFile $q4 -UseBasicParsing -TimeoutSec 1800
                            $ok = $true; break
                        } catch { Write-Host "[WARN] Mirror failed: $($_.Exception.Message)" }
                    }
                    if (-not $ok) { throw "Q4_K_M download failed. Place 'qwen-talker-0.6b-base-Q4_K_M.gguf' into $mdir manually." }
                }
            }
            if (-not (Test-Path -LiteralPath $orig)) {
                if ($activeKind -eq 'q8') { Copy-Item -LiteralPath $active -Destination $orig -Force }
            }
            if (-not (Test-Path -LiteralPath $orig)) { throw 'Original Q8_0 backup missing; refusing to overwrite the active model.' }
            Copy-Item -LiteralPath $q4 -Destination $active -Force
            Write-Host "[OK] Q4_K_M model activated (~2x faster inference). Original Q8_0 kept as: $orig"
        } else {
            if (Test-Path -LiteralPath $orig) {
                Copy-Item -LiteralPath $orig -Destination $active -Force
                Write-Host '[OK] Standard Q8_0 model restored.'
            } else {
                throw "Original Q8_0 backup not found ($orig). Launch the game to re-download it."
            }
        }
    }

    # ---------- restore ----------
    if ($action -eq 'restore') {
        if (-not $already) { Write-Host '[OK] DLL is already original. Nothing to restore.'; exit 0 }
        $bp = Get-ExistingBackup $dll
        if (-not $bp) { throw 'No backup found next to the DLL. Use Steam file verification to restore.' }
        $backupBytes = [IO.File]::ReadAllBytes($bp)
        if ((Sha256Hex $backupBytes) -ne $build.Original) { throw "Backup $bp is invalid or for another build. Use Steam file verification." }
        ReplaceVerified $dll $current $backupBytes $build.Original
        Write-Host "[OK] Original DLL restored from: $bp"
        Write-Host 'Voice preferences can be changed in the game settings.'
        exit 0
    }

    # ---------- patch / check ----------
    $edits = @($build.Edits) + @(@{
        o = $build.HwOffset; b = $build.HwBefore; a = $build.Blocks[$Backend]
        d = ("Hardware eligibility: allow; backend -> " + $Backend)
    })

    $source = [byte[]]$current.Clone()
    if ($already) {
        foreach ($e in $edits) { CopyInto $source $e.o (HexToBytes $e.b) }
        if ((Sha256Hex $source) -ne $build.Original) { throw 'Patched-state reconstruction failed. No changes made.' }
    }
    foreach ($e in $edits) {
        if (-not (MatchesAt $source $e.o (HexToBytes $e.b))) { throw ("Unexpected code bytes: " + $e.d + ". No changes made.") }
    }
    $output = [byte[]]$source.Clone()
    foreach ($e in $edits) {
        CopyInto $output $e.o (HexToBytes $e.a)
        Write-Host ("[OK] " + $e.d)
    }
    $outHash = Sha256Hex $output
    if ($outHash -ne $build.Patched[$Backend]) { throw ("Output hash mismatch (" + $outHash + "). No changes made.") }

    if ($action -eq 'check') {
        Write-Host '[OK] CHECK ONLY. No game files or settings were changed.'
        exit 0
    }

    $ownBackup = $dll + '.swyf.original'
    $bp = $null
    foreach ($s in @('.swyf.original', '.swyf-v23.original', '.swyf-v22.original')) {
        $cand = $dll + $s
        if (Test-Path -LiteralPath $cand) {
            if ((Sha256Hex ([IO.File]::ReadAllBytes($cand))) -eq $build.Original) { $bp = $cand; break }
        }
    }
    if ($bp) {
        Write-Host "[OK] Using existing backup: $bp"
    } else {
        # a stale backup from another game build is overwritten; Steam can always restore any build
        [IO.File]::WriteAllBytes($ownBackup, $source)
        if ((Sha256Hex ([IO.File]::ReadAllBytes($ownBackup))) -ne $build.Original) { throw 'Backup verification failed. No changes made.' }
        $bp = $ownBackup
        Write-Host "[INFO] Previous backup was for another build; wrote fresh backup: $bp"
    }

    if ($curHash -eq $outHash) {
        Write-Host "[OK] Already patched (backend: $Backend). DLL left unchanged."
    } else {
        ReplaceVerified $dll $current $output $build.Patched[$Backend]
        if ($already -or $legacy) {
            Write-Host "[OK] DLL updated: $curVariant$(if ($legacy) { ' (legacy)' }) -> $Backend (v$Version layout)"
        } else {
            Write-Host "[OK] DLL patched (backend: $Backend). Backup: $bp"
        }
    }

    # ---------- voice preferences ----------
    try {
        $key = 'HKCU:\Software\Jatater Worldwide\' + $GameName
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        New-ItemProperty -Path $key -Name 'Kolkata.Qwen3Tts_h1324939569' -PropertyType DWord -Value 0 -Force | Out-Null
        New-ItemProperty -Path $key -Name 'Kolkata.Dev.RussianSpeechProvider_h3030369888' -PropertyType DWord -Value 0 -Force | Out-Null
        Write-Host '[OK] Voice preference values written.'
    } catch {
        $Code = 2
        Write-Host ('[WARN] DLL is patched, but voice preference registry values were not saved: ' + $_.Exception.Message)
        Write-Host 'Select Qwen3 for non-English speech in the game settings.'
    }
    Write-Host 'Done. Start the game and test voice generation.'
    exit $Code
} catch {
    Write-Host ''
    Write-Host ('[FAIL] ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
    exit 1
}
