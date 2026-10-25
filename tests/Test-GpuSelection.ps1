param([string]$WorkerPath = '')
$ErrorActionPreference = 'Stop'
if (-not $WorkerPath) { $WorkerPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'payload/QwenTtsWorker.exe' }
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $WorkerPath).Path)
$selection = $assembly.GetType('GpuSelection', $true)
$deviceType = $assembly.GetType('GpuDevice', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$fields = [Reflection.BindingFlags]'Instance,NonPublic'
$checks = 0
function Assert($value, [string]$message) {
    if (-not $value) { throw "ASSERT: $message" }; $script:checks++
}
function Device([string]$name, [string]$description, [int]$type, [ulong]$memory) {
    $ctor = $deviceType.GetConstructors($fields)[0]
    $ctor.Invoke([object[]]@($name, $description, $type, $memory, [ulong]0))
}
function Select-Device([object[]]$devices) {
    $array = [Array]::CreateInstance($deviceType, $devices.Count)
    for ($i = 0; $i -lt $devices.Count; $i++) { $array.SetValue($devices[$i], $i) }
    $selection.GetMethod('Choose', $flags).Invoke($null, [object[]]@(,$array))
}
$intel = Device 'Vulkan0' 'Intel Iris Xe' 2 8589934592
$nvidia = Device 'Vulkan1' 'NVIDIA RTX 3050 Laptop' 1 4294967296
$cpu = Device 'CPU' 'Intel i5-12500H' 0 17179869184
$chosen = Select-Device @($cpu, $intel, $nvidia)
Assert ([Object]::ReferenceEquals($chosen, $nvidia)) 'Reported hybrid laptop: Vulkan1 discrete wins over Vulkan0 integrated with more shared memory'
Assert ([Object]::ReferenceEquals((Select-Device @($nvidia, $intel, $cpu)), $nvidia)) 'Registry ordering does not affect discrete preference'
$arc = Device 'Vulkan3' 'Intel Arc discrete' 1 8589934592
$amd = Device 'Vulkan2' 'AMD Radeon integrated' 2 17179869184
Assert ([Object]::ReferenceEquals((Select-Device @($amd, $arc)), $arc)) 'Choice uses native device type, not vendor name'
Assert ([Object]::ReferenceEquals((Select-Device @($nvidia, $arc)), $arc)) 'Among discrete GPUs prefer greater total VRAM'
$equal = Device 'Vulkan2' 'Equal discrete' 1 4294967296
Assert ([Object]::ReferenceEquals((Select-Device @($nvidia, $equal)), $nvidia)) 'Equal-memory GPUs retain stable registry order'
Assert ([Object]::ReferenceEquals((Select-Device @($cpu, $intel)), $intel)) 'Integrated-only computer still has explicit GPU support'
Assert ([Object]::ReferenceEquals((Select-Device @($nvidia)), $nvidia)) 'Single GPU works with a nonzero index'
$other = Device 'CUDA0' 'CUDA' 1 17179869184
Assert ([Object]::ReferenceEquals((Select-Device @($other, $intel)), $intel)) 'GPU mode selects only the supported Vulkan backend'
foreach ($devices in @(@($cpu), @(), @((Device 'Vulkan0' 'Invalid type' 0 1024)))) {
    $threw = $false
    try { Select-Device $devices | Out-Null } catch { $threw = $true }
    Assert $threw 'Missing/invalid Vulkan device fails instead of silently using CPU'
}
foreach ($case in @(@('Vulkan0',$true), @('Vulkan1',$true), @('Vulkan12',$true), @('Vulkan',$false), @('Vulkan-1',$false), @('Vulkan0x',$false), @('CPU',$false))) {
    Assert ($selection.GetMethod('IsVulkan', $flags).Invoke($null, [object[]]@($case[0])) -eq $case[1]) 'Validate native Vulkan device names'
}
Write-Host "PASS: $checks GPU selection assertions (synthetic GGML inventory, including the reported laptop)."
