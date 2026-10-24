param([Parameter(Mandatory=$true)][string]$ReferenceDirectory, [string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
# Developer-only build: requires PowerShell 7's bundled Roslyn and .NET Framework 4.7.2 reference assemblies.
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'payload/QwenTtsWorker.exe' }
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.dll')
Add-Type -Path (Join-Path $PSHOME 'Microsoft.CodeAnalysis.CSharp.dll')
$trees = [Microsoft.CodeAnalysis.SyntaxTree[]]@(
    [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Worker.cs'))),
    [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'AutomaticLogs.cs'))),
    [Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Qwen3Native.cs')))
)
$refs = [Microsoft.CodeAnalysis.MetadataReference[]]@('mscorlib.dll','System.dll','System.Core.dll' | ForEach-Object {
    [Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $ReferenceDirectory $_))
})
$options = [Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::ConsoleApplication).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release).WithDeterministic($true)
$compilation = [Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('QwenTtsWorker', $trees, $refs, $options)
$stream = [IO.File]::Create($OutputPath)
try { $result = $compilation.Emit($stream) } finally { $stream.Dispose() }
if (-not $result.Success) { $result.Diagnostics | ForEach-Object { Write-Host $_ }; throw 'Worker compilation failed.' }
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
