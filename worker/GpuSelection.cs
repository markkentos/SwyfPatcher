// Enumerate the exact GGML registry used by Qwen; Windows display order can differ.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;

internal sealed class GpuDevice
{
    internal readonly string Backend, Description;
    internal readonly int Type;
    internal readonly ulong TotalBytes, FreeBytes;
    internal GpuDevice(string backend, string description, int type, ulong totalBytes, ulong freeBytes)
    {
        Backend = backend; Description = description; Type = type;
        TotalBytes = totalBytes; FreeBytes = freeBytes;
    }
    internal string Kind { get { return Type == 1 ? "discrete" : "integrated"; } }
    internal string Details { get { return "backend=" + Backend + " type=" + Kind + " name=" + Description +
        " totalMiB=" + (TotalBytes / 1048576) + " freeMiB=" + (FreeBytes / 1048576); } }
}

internal static class GpuSelection
{
    // These exports are split across ggml.dll and ggml-base.dll in the pinned runtime.
    [DllImport("ggml", CallingConvention = CallingConvention.Cdecl)]
    private static extern UIntPtr ggml_backend_dev_count();
    [DllImport("ggml", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr ggml_backend_dev_get(UIntPtr index);
    [DllImport("ggml-base", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr ggml_backend_dev_name(IntPtr device);
    [DllImport("ggml-base", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr ggml_backend_dev_description(IntPtr device);
    [DllImport("ggml-base", CallingConvention = CallingConvention.Cdecl)]
    private static extern int ggml_backend_dev_type(IntPtr device);
    [DllImport("ggml-base", CallingConvention = CallingConvention.Cdecl)]
    private static extern void ggml_backend_dev_memory(IntPtr device, out UIntPtr free, out UIntPtr total);

    internal static bool IsVulkan(string name)
    {
        if (name == null || !name.StartsWith("Vulkan", StringComparison.Ordinal) || name.Length == 6) return false;
        for (int i = 6; i < name.Length; ++i) if (name[i] < '0' || name[i] > '9') return false;
        return true;
    }

    internal static GpuDevice Choose(IList<GpuDevice> devices)
    {
        GpuDevice best = null;
        foreach (var device in devices)
        {
            // ggml_backend_dev_type: CPU=0, discrete GPU=1, integrated GPU=2.
            if (!IsVulkan(device.Backend) || (device.Type != 1 && device.Type != 2)) continue;
            if (best == null || device.Type < best.Type ||
                (device.Type == best.Type && device.TotalBytes > best.TotalBytes)) best = device;
        }
        if (best == null) throw new IOException("No Vulkan GPU found. Select CPU in the patcher or check the Vulkan driver.");
        return best;
    }

    internal static GpuDevice Detect(Action<string> log)
    {
        var devices = new List<GpuDevice>();
        ulong count = ggml_backend_dev_count().ToUInt64();
        if (count > 256) throw new IOException("Invalid GGML device count.");
        for (ulong i = 0; i < count; ++i)
        {
            IntPtr handle = ggml_backend_dev_get(new UIntPtr(i));
            if (handle == IntPtr.Zero) continue;
            string name = Marshal.PtrToStringAnsi(ggml_backend_dev_name(handle));
            int type = ggml_backend_dev_type(handle);
            if (!IsVulkan(name) || (type != 1 && type != 2)) continue;
            string description = Marshal.PtrToStringAnsi(ggml_backend_dev_description(handle)) ?? "unknown";
            UIntPtr free, total; ggml_backend_dev_memory(handle, out free, out total);
            var device = new GpuDevice(name, description, type, total.ToUInt64(), free.ToUInt64());
            devices.Add(device); log("GPU_CANDIDATE " + device.Details);
        }
        var selected = Choose(devices);
        log("GPU_SELECTED " + selected.Details + " policy=discrete-first-then-total-memory");
        if (selected.Type == 2) log("GPU_WARNING Only integrated Vulkan graphics are available; speech may be slower than playback.");
        return selected;
    }
}
