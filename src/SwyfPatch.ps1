# SwyfPatcher - universal Qwen3 TTS patch for "Scam With Your Friends"
# Enables the local Qwen3 neural TTS on modest hardware and lets you switch
# the inference backend (Vulkan / CPU) with one command.
#
# Original fix: psihozniy (hardware-eligibility + timeout patch, v2.1 lineage).
# Adapted, rewritten as a dependency-free PowerShell tool and maintained by markkentos.
#
# Usage:  SwyfPatch.bat [--backend auto|cpu|vulkan] [--check | --restore] [game-folder]

param(
    [string]$Backend = 'auto',
    [switch]$Check,
    [switch]$Restore,
    [string]$GamePath = ''
)

$ErrorActionPreference = 'Stop'
$Version = '2.6'
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
$AfterA   = '0E052000040000320A0E087269DA0770512B080E087261DA077051' + ('00' * 112) + '172A'
$CpuA     = '0E087261DA077051' + ('00' * 131) + '172A'
$VulkanA  = '0E087269DA077051' + ('00' * 131) + '172A'
$AfterB   = '0E052000040000320A0E087294C40770512B080E08728CC4077051' + ('00' * 112) + '172A'

$Builds = @(
    @{
        Tag      = '2026-10-22'
        Original = 'F94B92369D2AC0F7C1F10A30AE6A1C7FC4CEE99C538693C162B1A7FDC02A2BB2'
        Patched  = @{
            auto   = '7FB0CD47103813A740E5CF5755055DFC11AF3E2F3A8F4F0F14296121C90C27B3'
            cpu    = '39D7DFE1D3A9E9E1376AAC1C3090393ED5B841F4CBC4D1C4E8006436F8A6893A'
            vulkan = '7308A9DC6EE1983A622C77270D0817A91AE4CCD53F9649E145B539D74CD47290'
        }
        Scripts  = '5432D089E0E9C93B1A74ADDAF27EC240758FC2A183EC913CA41D9949C46E0A84'
        Speech   = '7F5A3EC065E87D85705F14B36E490E7BF2B0A1C95300813E7D9D197836BECF6B'
        HwOffset = 0x1222CC
        HwBefore = '0E05200016000032500E0620DE1000002E090E062002100000333E0E062002100000331B0E07209F6900002E2C0E0720DF6700002E230E07204C7400002E1A0E0620DE100000330E0E0720852B0000FE0116FE012B04172B01160A0E08062D077261DA07702B057269DA07705102065F2C190320983A000032110420001800006A3208051AFE0416FE012A162A'
        Blocks   = @{ auto = $AfterA; cpu = $CpuA; vulkan = $VulkanA }
        Edits    = @(
            @{ o = 0x1216BC; b = '0000000000003E40'; a = '0000000000C07240'; d = 'Prompt cancellation: 30 -> 300 seconds' },
            @{ o = 0x121723; b = '0000000000003440'; a = '0000000000C07240'; d = 'First audio deadline: 20 -> 300 seconds' },
            @{ o = 0x121E26; b = '0A'; a = '03'; d = 'Voice reference: 10 -> 3 seconds' },
            @{ o = 0x122078; b = '0000000000003E40'; a = '0000000000005E40'; d = 'Chunk timeout: 30 -> 120 seconds' },
            @{ o = 0x122174; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare timeout: 20 -> 120 seconds' },
            @{ o = 0x122203; b = '0000000000003440'; a = '0000000000005E40'; d = 'Prepare deadline: 20 -> 120 seconds' }
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

try {
    # ---------- normalize arguments ----------
    $Backend = $Backend.ToLowerInvariant()
    if ($Backend -notin @('auto', 'cpu', 'vulkan')) { throw "Invalid --backend value: $Backend (use auto, cpu or vulkan)." }
    $action = 'patch'
    if ($Restore) { $action = 'restore' }
    elseif ($Check) { $action = 'check' }

    # ---------- locate the game ----------
    if ($GamePath) {
        if (-not (Test-Path -LiteralPath $GamePath)) { throw "Game folder not found: $GamePath" }
        $game = (Resolve-Path -LiteralPath $GamePath).Path
    } else {
        $found = @()
        foreach ($drv in [IO.DriveInfo]::GetDrives()) {
            if (-not $drv.IsReady) { continue }
            foreach ($rel in @('SteamLibrary\steamapps\common', 'Program Files (x86)\Steam\steamapps\common', 'Steam\steamapps\common', 'Program Files (x86)\steamapps\common')) {
                $p = Join-Path (Join-Path $drv.RootDirectory.FullName $rel) $GameName
                if (Test-Path -LiteralPath (Join-Path $p ($GameName + '_Data\Managed\Assembly-CSharp.dll'))) { $found += $p }
            }
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
    foreach ($b in $Builds) {
        if ($curHash -eq $b.Original) { $build = $b; break }
        foreach ($v in @('auto', 'cpu', 'vulkan')) {
            if ($b.Patched[$v] -and $curHash -eq $b.Patched[$v]) { $build = $b; $already = $true; $curVariant = $v; break }
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
    if ($already) { $state = "PATCHED (backend: $curVariant)" }
    Write-Host ("SwyfPatcher v$Version. Build: " + $build.Tag + " (state: $state)")

    if ((Sha256Hex ([IO.File]::ReadAllBytes($scripts))) -ne $build.Scripts) { throw 'Unsupported ScriptsAssDef.dll. Verify files in Steam. No changes made.' }
    if ($build.Speech) {
        if (-not (Test-Path -LiteralPath $speech)) { throw 'Kolkata.Speech.dll is missing. Verify files in Steam. No changes made.' }
        if ((Sha256Hex ([IO.File]::ReadAllBytes($speech))) -ne $build.Speech) { throw 'Unsupported Kolkata.Speech.dll. Verify files in Steam. No changes made.' }
    }
    Write-Host '[OK] All game DLL hashes match a supported build.'

    if ($action -ne 'check') {
        if (Get-Process -Name $GameName -ErrorAction SilentlyContinue) { throw 'Close the game first. No changes made.' }
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
    if ((Sha256Hex $output) -ne $build.Patched[$Backend]) { throw ("Output hash mismatch (" + (Sha256Hex $output) + "). No changes made.") }

    if ($action -eq 'check') {
        Write-Host '[OK] CHECK ONLY. No game files or settings were changed.'
        exit 0
    }

    $ownBackup = $dll + '.swyf.original'
    $bp = Get-ExistingBackup $dll
    if ($bp) {
        if ((Sha256Hex ([IO.File]::ReadAllBytes($bp))) -ne $build.Original) { throw "Existing backup $bp is invalid or for another build. Move it aside first. No changes made." }
        Write-Host "[OK] Using existing backup: $bp"
    } else {
        [IO.File]::WriteAllBytes($ownBackup, $source)
        if ((Sha256Hex ([IO.File]::ReadAllBytes($ownBackup))) -ne $build.Original) { throw 'Backup verification failed. No changes made.' }
        $bp = $ownBackup
    }

    if ($already -and $curVariant -eq $Backend) {
        Write-Host "[OK] Already patched (backend: $Backend). DLL left unchanged."
    } else {
        ReplaceVerified $dll $current $output $build.Patched[$Backend]
        if ($already) { Write-Host "[OK] Backend switched: $curVariant -> $Backend" }
        else { Write-Host "[OK] DLL patched (backend: $Backend). Backup: $bp" }
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
    exit 1
}
