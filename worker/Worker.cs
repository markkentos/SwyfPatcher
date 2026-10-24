// Binary pipe protocol compatible with the supplied 0.1.89-swyf Qwen worker.
// stdout is protocol-only. Diagnostics go to separate local files.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Qwen3TTS;

[assembly: System.Reflection.AssemblyTitle("SwyfPatcher Qwen TTS Worker")]
[assembly: System.Reflection.AssemblyProduct("SwyfPatcher")]
[assembly: System.Reflection.AssemblyVersion("2.9.2.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.9.2.0")]
[assembly: System.Reflection.AssemblyInformationalVersion("2.9.2")]

internal static class Worker
{
    internal const string Build = "2.9.2";
    internal const string Q4Hash = "4B468EC7B1F62B90EF4CA316C0AA57DEADFD54B2CF9651703EA753CEDAF04226";
    private static readonly object logLock = new object();
    private static StreamWriter logFile;
    private static AutomaticLogs diagnostics;
    private static string logDirectory;
    private static BinaryWriter output;
    private static IntPtr context;
    private static int generated, request;
    private static double peak, energy;
    private static BinaryWriter capture;
    private static readonly qt_log_cb nativeLog = (level, message, user) => Log("QWEN " + level + " " + message);
    private static readonly GgmlLog ggmlLog = (level, message, user) => Log("GGML " + level + " " + message);
    private static readonly qt_audio_chunk_cb onChunk = SendChunk;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void GgmlLog(int level, [MarshalAs(UnmanagedType.LPUTF8Str)] string message, IntPtr user);
    [DllImport("ggml-base", CallingConvention = CallingConvention.Cdecl)]
    private static extern void ggml_log_set(GgmlLog callback, IntPtr user);
    [DllImport("kernel32.dll")] private static extern uint SetErrorMode(uint mode);

    [DllImport("ucrtbase.dll", CallingConvention = CallingConvention.Cdecl, EntryPoint = "_putenv_s")]
    private static extern int PutEnvWindows(string name, string value);
    [DllImport("libSystem.B.dylib", CallingConvention = CallingConvention.Cdecl, EntryPoint = "setenv")]
    private static extern int SetEnvMac(string name, string value, int overwrite);
    [DllImport("libSystem.B.dylib", CallingConvention = CallingConvention.Cdecl, EntryPoint = "unsetenv")]
    private static extern int UnsetEnvMac(string name);
    private static void SetNativeEnvironment(string name, string value)
    {
        Environment.SetEnvironmentVariable(name, value);
        // GGML calls C getenv(). Updating only the managed/Win32 environment can
        // leave the CRT's cached environment unchanged, so update that too.
        int rc = Environment.OSVersion.Platform == PlatformID.Win32NT
            ? PutEnvWindows(name, value ?? "")
            : (value == null ? UnsetEnvMac(name) : SetEnvMac(name, value, 1));
        if (rc != 0) throw new IOException("Cannot set native environment: " + name);
    }

    // Only the failing model/backend combination opts into the compatibility path.
    // GGUF bytes and GPU selection are preserved. Flags are private to this process.
    internal static bool UseQ4GpuProfile(string hash, string backend)
    {
        return backend == "Vulkan0" && String.Equals(hash, Q4Hash, StringComparison.OrdinalIgnoreCase);
    }
    private static void ApplyQ4GpuProfile()
    {
        string[] flags = { "GGML_VK_DISABLE_F16", "GGML_VK_DISABLE_MMVQ", "GGML_VK_DISABLE_COOPMAT",
            "GGML_VK_DISABLE_COOPMAT2", "GGML_VK_DISABLE_GRAPH_OPTIMIZE", "GGML_VK_DISABLE_FUSION" };
        foreach (string flag in flags) { SetNativeEnvironment(flag, "1"); Log("PROFILE " + flag + "=1"); }
        // FORCE_MMVQ would otherwise contradict the explicitly selected path.
        SetNativeEnvironment("GGML_VK_FORCE_MMVQ", null);
    }
    private static void OpenLog()
    {
        string profile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "AppData", "LocalLow", "Jatater Worldwide", "Scam With Your Friends");
        diagnostics = AutomaticLogs.Open(profile, Environment.GetEnvironmentVariable("SWYF_QWEN_LOG_DIR"),
            Environment.GetEnvironmentVariable("SWYF_QWEN_CAPTURE"));
        if (diagnostics == null) return;
        logDirectory = diagnostics.DirectoryPath;
        logFile = diagnostics.Writer;
        Log("WORKER " + Build + " pid=" + Process.GetCurrentProcess().Id + " pointerBytes=" + IntPtr.Size);
        Log("DIAGNOSTICS directory=" + logDirectory + " capture=" + diagnostics.CaptureAudio);
    }
    private static void Log(string message)
    {
        try
        {
            lock (logLock)
                if (logFile != null && logFile.BaseStream.Position < 8 * 1024 * 1024)
                    logFile.WriteLine(DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture) + " " + (message.Length > 32768 ? message.Substring(0, 32768) : message).TrimEnd());
        }
        catch { /* Logging must never break inference or a native callback. */ }
    }
    private static string HashFile(string path)
    {
        using (var stream = File.OpenRead(path))
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
    }
    private static bool SupportedLanguage(string value)
    {
        return Array.IndexOf(new[] { "English", "Chinese", "Japanese", "Korean", "German", "French", "Russian", "Portuguese", "Spanish", "Italian" }, value) >= 0;
    }
    private static string NativeError()
    {
        IntPtr pointer = Native.qt_last_error();
        return pointer == IntPtr.Zero ? "no native detail" : Marshal.PtrToStringAnsi(pointer);
    }
    private static void Load(string model, string codec, string backend)
    {
        if (context != IntPtr.Zero || (backend != "CPU" && backend != "Vulkan0")) throw new InvalidDataException("Invalid Qwen load request.");
        string hash = HashFile(model);
        bool safe = UseQ4GpuProfile(hash, backend);
        Log("LOAD modelSHA256=" + hash + " backend=" + backend + " q4GpuCompatibility=" + safe);
        SetNativeEnvironment("GGML_BACKEND", backend);
        if (safe) ApplyQ4GpuProfile();
        // Install both callbacks before loading backends; GGML logs contain actual device selection.
        Native.qt_log_set(nativeLog, IntPtr.Zero);
        ggml_log_set(ggmlLog, IntPtr.Zero);
        string root = Path.GetDirectoryName(typeof(Worker).Assembly.Location);
        Native.ggml_backend_load_all_from_path(Path.Combine(root, "cpu"));
        if (backend == "Vulkan0") Native.ggml_backend_load_all_from_path(Path.Combine(root, "gpu"));
        qt_init_params ip;
        Native.qt_init_default_params(out ip);
        ip.talker_path = model; ip.codec_path = codec;
        if (safe) ip.use_fa = false;
        Log("INIT use_fa=" + ip.use_fa + " clamp_fp16=" + ip.clamp_fp16 + " initStructBytes=" + Marshal.SizeOf(typeof(qt_init_params)) + " ttsStructBytes=" + Marshal.SizeOf(typeof(qt_tts_params)));
        context = Native.qt_init(in ip);
        if (context == IntPtr.Zero) throw new IOException("Qwen model initialization failed: " + NativeError());
        output.Write(1); output.Write(1); output.Flush();
        Log("READY");
    }
    private static void StartCapture()
    {
        if (request > 6 || logDirectory == null || (diagnostics == null || !diagnostics.CaptureAudio)) return;
        try
        {
            string path = Path.Combine(logDirectory, "audio-" + Process.GetCurrentProcess().Id + "-" + request.ToString("D4") + ".wav");
            capture = new BinaryWriter(new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.Read));
            capture.Write(Encoding.ASCII.GetBytes("RIFF")); capture.Write(36);
            capture.Write(Encoding.ASCII.GetBytes("WAVEfmt ")); capture.Write(16); capture.Write((short)1); capture.Write((short)1);
            capture.Write(24000); capture.Write(48000); capture.Write((short)2); capture.Write((short)16);
            capture.Write(Encoding.ASCII.GetBytes("data")); capture.Write(0); capture.Flush();
            Log("CAPTURE " + Path.GetFileName(path));
        }
        catch (Exception e) { Log("CAPTURE_ERROR " + e.Message); StopCapture(); }
    }
    private static void StopCapture()
    {
        var current = capture; capture = null;
        try { if (current != null) current.Dispose(); } catch { }
    }
    private static void Capture(float[] pcm)
    {
        if (capture == null) return;
        try
        {
            foreach (float value in pcm) capture.Write((short)(Math.Max(-1.0f, Math.Min(1.0f, value)) * 32767));
            long end = capture.BaseStream.Position;
            capture.BaseStream.Position = 4; capture.Write((int)end - 8);
            capture.BaseStream.Position = 40; capture.Write((int)end - 44);
            capture.BaseStream.Position = end; capture.Flush();
        }
        catch (Exception e) { Log("CAPTURE_ERROR " + e.Message); StopCapture(); }
    }
    private static bool SendChunk(IntPtr pointer, int count, IntPtr unused)
    {
        try
        {
            if (count <= 0 || count > 720000 || generated + count > 720000) { Log("INVALID_CHUNK samples=" + count); return false; }
            var pcm = new float[count]; Marshal.Copy(pointer, pcm, 0, count);
            foreach (float value in pcm)
            {
                if (Single.IsNaN(value) || Single.IsInfinity(value)) { Log("NONFINITE_AUDIO"); return false; }
                peak = Math.Max(peak, Math.Abs(value)); energy += (double)value * value;
            }
            var bytes = new byte[count * 4]; Buffer.BlockCopy(pcm, 0, bytes, 0, bytes.Length);
            output.Write(2); output.Write(count); output.Write(bytes); output.Flush();
            if (generated == 0) Log("FIRST_AUDIO request=" + request);
            generated += count; Capture(pcm); return true;
        }
        catch (Exception e) { Log("CHUNK_ERROR " + e.Message); return false; }
    }
    private static void Synthesize(string text, string language, float[] reference)
    {
        ++request; generated = 0; peak = 0; energy = 0;
        Log("REQUEST " + request + " language=" + language + " refSamples=" + reference.Length + " text=" + text.Replace("\r", " ").Replace("\n", " "));
        var pinned = GCHandle.Alloc(reference, GCHandleType.Pinned);
        var voice = new qt_voice_ref(); var audio = new qt_audio(); var watch = Stopwatch.StartNew();
        try
        {
            if (Native.qt_extract_voice_ref(context, pinned.AddrOfPinnedObject(), reference.Length, out voice) != qt_status.QT_STATUS_OK)
                throw new IOException("Qwen could not encode the voice reference: " + NativeError());
            qt_tts_params tp; Native.qt_tts_default_params(out tp);
            tp.text = text; tp.lang = language; tp.ref_spk_emb = voice.ref_spk_emb; tp.ref_spk_dim = voice.ref_spk_dim;
            tp.ref_codes = IntPtr.Zero; tp.ref_T = 0; tp.max_new_tokens = 360; tp.on_chunk = onChunk;
            // Defaults, reference handling, frame limit and protocol match the original worker.
            StartCapture();
            qt_status status = Native.qt_synthesize(context, in tp, out audio);
            if (status != qt_status.QT_STATUS_OK) throw new IOException("Qwen speech generation failed: " + status + ": " + NativeError());
            if (generated == 0 && audio.samples != IntPtr.Zero) SendChunk(audio.samples, audio.n_samples, IntPtr.Zero);
            if (generated == 0) throw new IOException("Qwen returned empty speech.");
            Log("COMPLETE request=" + request + " samples=" + generated + " ms=" + watch.ElapsedMilliseconds + " peak=" + peak.ToString("G6", CultureInfo.InvariantCulture) + " rms=" + Math.Sqrt(energy / generated).ToString("G6", CultureInfo.InvariantCulture));
        }
        finally
        {
            StopCapture();
            Native.qt_audio_free(ref audio); Native.qt_voice_ref_free(ref voice); pinned.Free();
        }
    }
    public static int Main(string[] args)
    {
        if (Environment.OSVersion.Platform == PlatformID.Win32NT) SetErrorMode(3);
        OpenLog();
        try
        {
            using (output = new BinaryWriter(Console.OpenStandardOutput()))
            using (var input = new BinaryReader(Console.OpenStandardInput()))
            {
                try
                {
                    while (true)
                    {
                        int command;
                        try { command = input.ReadInt32(); } catch (EndOfStreamException) { Log("INPUT_CLOSED"); return 0; }
                        if (command == 1) Load(input.ReadString(), input.ReadString(), input.ReadString());
                        else if (command == 2)
                        {
                            if (context == IntPtr.Zero) throw new InvalidOperationException("Qwen is not loaded.");
                            string text = input.ReadString(), language = input.ReadString();
                            if (text.Length == 0 || text.Length > 2000 || !SupportedLanguage(language)) throw new InvalidDataException("Invalid Qwen speech request.");
                            int count = input.ReadInt32();
                            if (count < 2400 || count > 240000) throw new InvalidDataException("Invalid Qwen reference length.");
                            byte[] bytes = input.ReadBytes(count * 4);
                            if (bytes.Length != count * 4) throw new EndOfStreamException();
                            var pcm = new float[count]; Buffer.BlockCopy(bytes, 0, pcm, 0, bytes.Length);
                            foreach (float value in pcm) if (Single.IsNaN(value) || Single.IsInfinity(value)) throw new InvalidDataException("Invalid reference sample.");
                            Synthesize(text, language, pcm); output.Write(3); output.Flush();
                        }
                        else throw new InvalidDataException("Unknown Qwen command.");
                    }
                }
                catch (Exception e)
                {
                    Log("ERROR " + e);
                    try { output.Write(4); output.Write(e.Message); output.Flush(); } catch { }
                    return 1;
                }
                finally { if (context != IntPtr.Zero) { Native.qt_free(context); context = IntPtr.Zero; } }
            }
        }
        finally { Log("WORKER_EXIT"); if (diagnostics != null) diagnostics.Dispose(); }
    }
}
