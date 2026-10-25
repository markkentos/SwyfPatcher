Qwen3Native.cs is from lookbe/qwen3-tts-unity, revision 8fcffb4dfc544117258341ef2e4eace316016430, Runtime/Native/Qwen3Native.cs. Its MIT notice is in LICENSE-lookbe.txt.

Worker.cs is a local replacement implementing the observed binary pipe protocol of the supplied game's QwenTtsWorker.exe. It uses the existing native runtime; no game binaries or model weights are distributed here. AutomaticLogs.cs provides local diagnostic storage. GpuSelection.cs uses the pinned GGML device registry to choose a Vulkan adapter. The patcher's MIT license applies to the local implementation files.

Build-Worker.ps1 uses Roslyn bundled with PowerShell 7 and the official Microsoft.NETFramework.ReferenceAssemblies.net472 package 1.0.3. Build tools/reference assemblies are not shipped in the archive. The resulting worker targets .NET Framework 4.7.2, AnyCPU without Prefer32Bit, and runs as a 64-bit process on 64-bit Windows.
