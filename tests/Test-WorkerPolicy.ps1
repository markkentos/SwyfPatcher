param([string]$WorkerPath = '')
$ErrorActionPreference = 'Stop'
if (-not $WorkerPath) { $WorkerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'payload/QwenTtsWorker.exe' }
# Does not load native DLLs or execute the worker's entry point.
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $WorkerPath).Path)
$type = $assembly.GetType('Worker', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$method = $type.GetMethod('UseQ4GpuProfile', $flags)
$q4 = '4B468EC7B1F62B90EF4CA316C0AA57DEADFD54B2CF9651703EA753CEDAF04226'
$q8 = 'D54DBAF10591421FA764ED630D764EFA717AE40CD959BD48C66D4EB1AF226426'
foreach ($case in @(@($q4,'Vulkan0',$true), @($q4,'CPU',$false), @($q8,'Vulkan0',$false), @('unknown','Vulkan0',$false))) {
    $actual = $method.Invoke($null, [object[]]@($case[0], $case[1]))
    if ($actual -ne $case[2]) { throw "Wrong GPU policy: $($case[0]) / $($case[1])" }
}
Write-Host 'PASS: worker compatibility applies only to verified Q4 + Vulkan0.'
