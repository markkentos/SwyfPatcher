// Local diagnostics for normal Steam/EXE launches; never writes to stdout.
using System;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

internal sealed class AutomaticLogs : IDisposable
{
    internal readonly string DirectoryPath;
    internal readonly bool CaptureAudio;
    internal readonly StreamWriter Writer;
    private readonly FileStream lease;
    private static readonly Regex SessionName = new Regex(@"^session-\d{8}-\d{6}-\d{3}-[a-f0-9]{32}$");
    private static readonly Regex OwnedFile = new Regex(@"^(session\.log|\.active|audio-\d+-\d{4}\.wav)$");

    private AutomaticLogs(string directory, bool captureAudio, bool automatic)
    {
        DirectoryPath = directory;
        CaptureAudio = captureAudio;
        Directory.CreateDirectory(directory);
        if (automatic) lease = new FileStream(Path.Combine(directory, ".active"), FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
        try
        {
            string name = automatic ? "session.log" : "qwen-" + Guid.NewGuid().ToString("N") + ".log";
            Writer = new StreamWriter(new FileStream(Path.Combine(directory, name), FileMode.CreateNew, FileAccess.Write, FileShare.Read), new UTF8Encoding(false));
            Writer.AutoFlush = true;
        }
        catch { if (lease != null) lease.Dispose(); throw; }
    }

    internal static AutomaticLogs Open(string profile, string requested, string captureSetting)
    {
        // An explicit test path stays flat for existing diagnostic tools.
        if (!String.IsNullOrWhiteSpace(requested))
        {
            try { return new AutomaticLogs(requested, captureSetting != "0", false); }
            catch { /* Fall back to the writable Unity profile. */ }
        }
        try
        {
            string root = Path.Combine(profile, "swyf-qwen-logs");
            string name = "session-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff", CultureInfo.InvariantCulture) + "-" + Guid.NewGuid().ToString("N");
            var result = new AutomaticLogs(Path.Combine(root, name), captureSetting != "0", true);
            Prune(root);
            return result;
        }
        catch { return null; } // Disk/permission problems must not disable speech.
    }

    internal static void Prune(string root)
    {
        try
        {
            var folders = new DirectoryInfo(root).GetDirectories("session-*");
            Array.Sort(folders, (a, b) => String.CompareOrdinal(b.Name, a.Name));
            int kept = 0;
            foreach (var folder in folders)
            {
                if (!SessionName.IsMatch(folder.Name) || (folder.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                // Never delete unrelated files, links, subfolders or a live worker's log.
                var files = folder.GetFiles();
                if (folder.GetDirectories().Length != 0 || Array.Exists(files, f => !OwnedFile.IsMatch(f.Name) || (f.Attributes & FileAttributes.ReparsePoint) != 0)) continue;
                if (!File.Exists(Path.Combine(folder.FullName, "session.log")) || !File.Exists(Path.Combine(folder.FullName, ".active"))) continue;
                if (++kept <= 10) continue;
                try
                {
                    using (File.Open(Path.Combine(folder.FullName, ".active"), FileMode.Open, FileAccess.ReadWrite, FileShare.None)) { }
                    foreach (var file in files) file.Delete();
                    folder.Delete();
                }
                catch { /* A live or inaccessible session is preserved. */ }
            }
        }
        catch { }
    }

    public void Dispose()
    {
        try { Writer.Dispose(); } catch { }
        try { if (lease != null) lease.Dispose(); } catch { }
    }
}
