param([string]$WorkerPath = '')
$ErrorActionPreference = 'Stop'
if (-not $WorkerPath) { $WorkerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'payload/QwenTtsWorker.exe' }
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $WorkerPath).Path)
$type = $assembly.GetType('AutomaticLogs', $true)
$worker = $assembly.GetType('Worker', $true)
$static = [Reflection.BindingFlags]'Static,NonPublic'
$instance = [Reflection.BindingFlags]'Instance,NonPublic'
$root = Join-Path ([IO.Path]::GetTempPath()) ('swyf-autolog-tests-' + [Guid]::NewGuid().ToString('N'))
$checks = 0
$opened = New-Object 'System.Collections.Generic.List[object]'
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "ASSERT: $message" }
    $script:checks++
}
function Open-Logs([string]$profile, [string]$requested = '', [string]$capture = '') {
    $result = $type.GetMethod('Open', $static).Invoke($null, [object[]]@($profile, $requested, $capture))
    if ($null -ne $result) { $opened.Add($result) }
    return $result
}
function Field($obj, [string]$name) { $type.GetField($name, $instance).GetValue($obj) }
try {
    $profile = Join-Path $root 'profile with spaces'
    $session = Open-Logs $profile
    $folder = Field $session 'DirectoryPath'
    Assert ($folder -like "$profile*swyf-qwen-logs*session-*") 'No environment overrides needed for default session folder'
    Assert (Field $session 'CaptureAudio') 'Generated audio is captured by default'
    (Field $session 'Writer').WriteLine('READY: native log fixture')
    Assert ([IO.File]::ReadAllText((Join-Path $folder 'session.log')) -match 'READY') 'Log is flushed while worker remains open'

    # Use the real worker capture methods without loading native libraries.
    $worker.GetField('diagnostics', $static).SetValue($null, $session)
    $worker.GetField('logDirectory', $static).SetValue($null, $folder)
    for ($i = 1; $i -le 7; $i++) {
        $worker.GetField('request', $static).SetValue($null, $i)
        $worker.GetMethod('StartCapture', $static).Invoke($null, @())
        if ($i -le 6) {
            $worker.GetMethod('Capture', $static).Invoke($null, [object[]]@(,[single[]]@(0.5, -0.5)))
            $capture = $worker.GetField('capture', $static).GetValue($null)
            $capture.Dispose()
            $worker.GetField('capture', $static).SetValue($null, $null)
        }
    }
    $wav = @(Get-ChildItem -LiteralPath $folder -Filter '*.wav')
    Assert ($wav.Count -eq 6) 'Automatic WAV capture stops after six replies'
    $bytes = [IO.File]::ReadAllBytes($wav[0].FullName)
    Assert ($bytes.Length -eq 48 -and [BitConverter]::ToInt32($bytes, 40) -eq 4) 'WAV header updated before worker exit'
    Assert ([BitConverter]::ToInt16($bytes, 44) -eq 16383 -and [BitConverter]::ToInt16($bytes, 46) -eq -16383) 'WAV contains generated PCM samples'

    # Disk/close failures in optional recording must not propagate into speech.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
public class BrokenCaptureStream : MemoryStream {
    public override void Write(byte[] b, int o, int c) { throw new IOException("simulated disk full"); }
    protected override void Dispose(bool disposing) { throw new IOException("simulated close failure"); }
}
'@
    $brokenWriter = [IO.BinaryWriter]::new([BrokenCaptureStream]::new())
    $worker.GetField('capture', $static).SetValue($null, $brokenWriter)
    $worker.GetMethod('Capture', $static).Invoke($null, [object[]]@(,[single[]]@(0.5)))
    Assert ($null -eq $worker.GetField('capture', $static).GetValue($null)) 'Disk failure disables recording without propagating into speech'

    $flat = Join-Path $root 'explicit-test'
    $override = Open-Logs $profile $flat '0'
    Assert ((Field $override 'DirectoryPath') -eq $flat -and -not (Field $override 'CaptureAudio')) 'Explicit flat test path and audio opt-out preserved'
    $worker.GetField('diagnostics', $static).SetValue($null, $override)
    $worker.GetField('logDirectory', $static).SetValue($null, $flat)
    $worker.GetField('request', $static).SetValue($null, 1)
    $worker.GetMethod('StartCapture', $static).Invoke($null, @())
    Assert (@(Get-ChildItem -LiteralPath $flat -Filter '*.wav').Count -eq 0) 'Audio opt-out prevents capture'
    $override.Dispose()

    $blocked = Join-Path $root 'not-a-directory'
    [IO.File]::WriteAllText($blocked, 'preserve')
    $fallback = Open-Logs $profile $blocked
    Assert ((Field $fallback 'DirectoryPath') -like "$profile*") 'Bad override falls back to automatic profile logs'
    $fallback.Dispose()
    Assert ($null -eq (Open-Logs $blocked)) 'No writable log path returns safely without breaking inference'
    Assert ([IO.File]::ReadAllText($blocked) -eq 'preserve') 'Logging failures do not overwrite unrelated files'

    $logRoot = Join-Path $profile 'swyf-qwen-logs'
    $foreign = Join-Path $logRoot ('session-20000101-000000-000-' + ('a' * 32))
    New-Item -ItemType Directory -Path $foreign | Out-Null
    foreach ($name in @('session.log', '.active', 'my-notes.txt')) { [IO.File]::WriteAllText((Join-Path $foreign $name), 'preserve') }
    for ($i = 0; $i -lt 14; $i++) { $recent = Open-Logs $profile; $recent.Dispose() }
    Assert (Test-Path -LiteralPath (Join-Path $folder 'session.log')) 'Rotation preserves a live worker session'
    Assert (Test-Path -LiteralPath (Join-Path $foreign 'my-notes.txt')) 'Rotation preserves folders containing unrelated files'
    $session.Dispose()
    $type.GetMethod('Prune', $static).Invoke($null, [object[]]@([string]$logRoot))
    $retained = @(Get-ChildItem -LiteralPath $logRoot -Directory | Where-Object { $_.FullName -ne $foreign })
    Assert ($retained.Count -eq 10) 'Rotation retains ten owned sessions after workers exit'
    Assert (@(Get-ChildItem -LiteralPath $flat -Filter '*.log').Count -eq 1) 'Rotation never touches explicit diagnostic folders'
    Write-Host "PASS: $checks automatic logging assertions. No game/native library required."
} finally {
    foreach ($item in $opened) { $item.Dispose() }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
