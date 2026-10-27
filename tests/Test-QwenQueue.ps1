param([Parameter(Mandatory = $true)][string]$GameRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/SwyfPatch.ps1')

# Execute the actual game's wait predicate with stand-ins for Unity time/provider state.
# Metadata tokens are resolved by name, then rebound to those stand-ins. No game is launched.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using System.Reflection.Metadata;
using System.Reflection.Metadata.Ecma335;
using System.Reflection.PortableExecutable;

public static class QwenQueueProbe {
    public sealed class Request {
        public bool Cancelled;
        public double FirstAudioAt = -1;
        public double StartedAt;
    }
    public sealed class Provider {
        public bool HasBufferedAudio { get; set; }
        public int Status { get; set; }
    }
    public sealed class Owner { public Provider qwenTTS = new Provider(); }
    public sealed class Closure {
        public Request request = new Request();
        public Owner owner = new Owner();
    }
    public sealed class Runner {
        public Func<Closure, bool> Wait;
        public Func<double, double, double, bool, bool> SharedWatchdog;
    }
    public static double Now { get; set; }

    static MethodDefinitionHandle Find(MetadataReader reader, string owner, string method) {
        foreach (var typeHandle in reader.TypeDefinitions) {
            var type = reader.GetTypeDefinition(typeHandle);
            if (reader.GetString(type.Name) != owner) continue;
            foreach (var handle in type.GetMethods())
                if (reader.GetString(reader.GetMethodDefinition(handle).Name) == method) return handle;
        }
        throw new InvalidOperationException("Game method missing: " + owner + "." + method);
    }
    static string MethodName(MetadataReader reader, int token) {
        var handle = MetadataTokens.EntityHandle(token);
        if (handle.Kind == HandleKind.MethodDefinition)
            return reader.GetString(reader.GetMethodDefinition((MethodDefinitionHandle)handle).Name);
        if (handle.Kind == HandleKind.MemberReference)
            return reader.GetString(reader.GetMemberReference((MemberReferenceHandle)handle).Name);
        throw new InvalidOperationException("Unsupported method token");
    }
    static void Init(DynamicILInfo info, byte[] code, int stack) {
        info.SetLocalSignature(SignatureHelper.GetLocalVarSigHelper().GetSignature());
        info.SetCode(code, stack);
    }
    public static Runner Load(string path) {
        using (var file = File.OpenRead(path))
        using (var pe = new PEReader(file)) {
            var reader = pe.GetMetadataReader();
            var sharedHandle = Find(reader, "PocketTtsSingleton", "HasSpeechStalled");
            var sharedBody = pe.GetMethodBody(reader.GetMethodDefinition(sharedHandle).RelativeVirtualAddress);
            var shared = new DynamicMethod("shared", typeof(bool), new[] { typeof(double), typeof(double), typeof(double), typeof(bool) });
            Init(shared.GetDynamicILInfo(), sharedBody.GetILBytes(), sharedBody.MaxStack);
            var handle = Find(reader, "<>c__DisplayClass80_0", "<ProcessSpeakQueue>b__6");
            var body = pe.GetMethodBody(reader.GetMethodDefinition(handle).RelativeVirtualAddress);
            if (!body.LocalSignature.IsNil) throw new InvalidOperationException("Unexpected predicate locals");
            var code = body.GetILBytes();
            var method = new DynamicMethod("wait", typeof(bool), new[] { typeof(Closure) });
            var info = method.GetDynamicILInfo();
            var ops = new Dictionary<short, OpCode>();
            foreach (var f in typeof(OpCodes).GetFields(BindingFlags.Static | BindingFlags.Public))
                if (f.FieldType == typeof(OpCode)) { var op = (OpCode)f.GetValue(null); ops[op.Value] = op; }
            for (int i = 0; i < code.Length;) {
                short value = code[i++];
                if (value == 0xfe) value = (short)(0xfe00 | code[i++]);
                var op = ops[value];
                int size;
                switch (op.OperandType) {
                    case OperandType.InlineNone: size = 0; break;
                    case OperandType.ShortInlineBrTarget:
                    case OperandType.ShortInlineI:
                    case OperandType.ShortInlineVar: size = 1; break;
                    case OperandType.InlineVar: size = 2; break;
                    case OperandType.InlineBrTarget:
                    case OperandType.InlineI:
                    case OperandType.ShortInlineR: size = 4; break;
                    case OperandType.InlineI8:
                    case OperandType.InlineR: size = 8; break;
                    case OperandType.InlineField: {
                        size = 4;
                        var field = reader.GetFieldDefinition((FieldDefinitionHandle)MetadataTokens.EntityHandle(BitConverter.ToInt32(code, i)));
                        string name = reader.GetString(field.Name);
                        FieldInfo replacement;
                        switch (name) {
                            case "request": replacement = typeof(Closure).GetField("request"); break;
                            case "<>4__this": replacement = typeof(Closure).GetField("owner"); break;
                            case "qwenTTS": replacement = typeof(Owner).GetField("qwenTTS"); break;
                            case "Cancelled": case "FirstAudioAt": case "StartedAt": replacement = typeof(Request).GetField(name); break;
                            default: throw new InvalidOperationException("Unexpected field: " + name);
                        }
                        Array.Copy(BitConverter.GetBytes(info.GetTokenFor(replacement.FieldHandle)), 0, code, i, 4);
                        break;
                    }
                    case OperandType.InlineMethod: {
                        size = 4;
                        string name = MethodName(reader, BitConverter.ToInt32(code, i));
                        int token;
                        switch (name) {
                            case "HasSpeechStalled": token = info.GetTokenFor(shared); break;
                            case "get_realtimeSinceStartupAsDouble": token = info.GetTokenFor(typeof(QwenQueueProbe).GetMethod("get_Now").MethodHandle); break;
                            case "get_HasBufferedAudio": case "get_Status": token = info.GetTokenFor(typeof(Provider).GetMethod(name).MethodHandle); break;
                            default: throw new InvalidOperationException("Unexpected call: " + name);
                        }
                        Array.Copy(BitConverter.GetBytes(token), 0, code, i, 4);
                        break;
                    }
                    default: throw new InvalidOperationException("Unexpected operand: " + op.OperandType);
                }
                i += size;
            }
            Init(info, code, body.MaxStack);
            return new Runner {
                Wait = (Func<Closure, bool>)method.CreateDelegate(typeof(Func<Closure, bool>)),
                SharedWatchdog = (Func<double, double, double, bool, bool>)shared.CreateDelegate(typeof(Func<double, double, double, bool, bool>))
            };
        }
    }
}
'@

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('swyf-queue-' + [Guid]::NewGuid().ToString('N'))
$checks = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw "ASSERT: $message" }
    $script:checks++
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $context = Get-Context $GameRoot
    Assert ($context.Build.Tag -eq '2026-10-26') 'Supplied 0.1.92 fixture'
    $plan = Get-PatchPlan $context 'auto' 10
    $original = Join-Path $testRoot 'original.dll'; $patched = Join-Path $testRoot 'patched.dll'
    [IO.File]::WriteAllBytes($original, $plan.Source)
    [IO.File]::WriteAllBytes($patched, $plan.Output)
    $before = [QwenQueueProbe]::Load($original)
    $after = [QwenQueueProbe]::Load($patched)
    $state = [QwenQueueProbe+Closure]::new()
    foreach ($seconds in @(0, 29.9, 30, 44, 119, 299.9, 300, 301)) {
        [QwenQueueProbe]::Now = $seconds
        Assert ($before.Wait.Invoke($state) -eq ($seconds -ge 30)) "Original first-audio wait at $seconds seconds"
        Assert ($after.Wait.Invoke($state) -eq ($seconds -ge 300)) "Patched first-audio wait at $seconds seconds"
    }
    $state.request.StartedAt = 100
    [QwenQueueProbe]::Now = 399.9
    Assert (-not $after.Wait.Invoke($state)) 'Deadline is relative to request start'
    [QwenQueueProbe]::Now = 400
    Assert ($after.Wait.Invoke($state)) 'Finite 300-second deadline'
    $state.request.StartedAt = 0; [QwenQueueProbe]::Now = 1
    $state.request.Cancelled = $true
    Assert ($after.Wait.Invoke($state)) 'Hang-up cancellation exits immediately'
    $state.request.Cancelled = $false; $state.request.FirstAudioAt = 0
    Assert ($after.Wait.Invoke($state)) 'First audio exits immediately'
    $state.request.FirstAudioAt = -1; $state.owner.qwenTTS.HasBufferedAudio = $true
    Assert ($after.Wait.Invoke($state)) 'Buffered audio exits immediately'
    $state.owner.qwenTTS.HasBufferedAudio = $false; $state.owner.qwenTTS.Status = -1
    Assert ($after.Wait.Invoke($state)) 'Provider error exits immediately'
    $state.owner.qwenTTS.Status = 1
    Assert (-not $after.Wait.Invoke($state)) 'Healthy provider without audio keeps waiting'
    foreach ($started in @($false, $true)) {
        foreach ($seconds in @(29, 30, 119, 120, 299, 300)) {
            Assert ($before.SharedWatchdog.Invoke($seconds, 0, 0, $started) -eq $after.SharedWatchdog.Invoke($seconds, 0, 0, $started)) 'Shared playback/MOSS watchdog unchanged'
        }
    }
    Write-Host "PASS: $checks queue assertions; actual game IL executed with isolated time/provider state. No Unity/native synthesis."
} finally { if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force } }
