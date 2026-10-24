using System;
using System.Runtime.InteropServices;

namespace Qwen3TTS
{
    public enum qt_status
    {
        QT_STATUS_OK = 0,
        QT_STATUS_INVALID_PARAMS = -1,
        QT_STATUS_MODE_INVALID = -2,
        QT_STATUS_GENERATE_FAILED = -3,
        QT_STATUS_OOM = -4,
        QT_STATUS_CANCELLED = -5,
    }

    public enum qt_log_level
    {
        QT_LOG_DEBUG = 0,
        QT_LOG_INFO = 1,
        QT_LOG_WARN = 2,
        QT_LOG_ERROR = 3,
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct qt_audio
    {
        public IntPtr samples;      // mono PCM, malloc allocated
        public int n_samples;    // length in samples
        public int sample_rate;  // 24000 (codec rate)
        public int channels;     // 1 (mono)
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct qt_init_params
    {
        public int abi_version;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string talker_path;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string codec_path;
        [MarshalAs(UnmanagedType.I1)] public bool use_fa;
        [MarshalAs(UnmanagedType.I1)] public bool clamp_fp16;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct qt_voice_ref
    {
        public IntPtr ref_spk_emb;
        public int ref_spk_dim;
        public IntPtr ref_codes;
        public int ref_T;
        public int num_codebooks;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool qt_cancel_cb(IntPtr user_data);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public delegate bool qt_audio_chunk_cb(IntPtr samples, int n_samples, IntPtr user_data);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void qt_log_cb(qt_log_level level, [MarshalAs(UnmanagedType.LPUTF8Str)] string msg, IntPtr user_data);

    [StructLayout(LayoutKind.Sequential)]
    public struct qt_tts_params
    {
        public int abi_version;

        [MarshalAs(UnmanagedType.LPUTF8Str)] public string text;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string lang;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string instruct;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string speaker;

        public IntPtr ref_audio_24k;
        public int ref_n_samples;
        [MarshalAs(UnmanagedType.LPUTF8Str)] public string ref_text;

        public long seed;
        public int max_new_tokens;
        [MarshalAs(UnmanagedType.I1)] public bool do_sample;
        public float temperature;
        public int top_k;
        public float top_p;
        public float repetition_penalty;
        [MarshalAs(UnmanagedType.I1)] public bool subtalker_do_sample;
        public float subtalker_temperature;
        public int subtalker_top_k;
        public float subtalker_top_p;

        [MarshalAs(UnmanagedType.LPUTF8Str)] public string dump_dir;

        public qt_cancel_cb cancel;
        public IntPtr cancel_user_data;

        public qt_audio_chunk_cb on_chunk;
        public IntPtr on_chunk_user_data;

        public float codec_chunk_sec;
        public float codec_left_context_sec;

        public IntPtr ref_spk_emb;
        public int ref_spk_dim;
        public IntPtr ref_codes;
        public int ref_T;
    }

    public static class Native
    {
        private const string GgmlDll = "ggml";
        private const string LibName = "qwen3";

        [DllImport(GgmlDll, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ggml_backend_load_all();

        [DllImport(GgmlDll, CallingConvention = CallingConvention.Cdecl)]
        public static extern void ggml_backend_load_all_from_path([MarshalAs(UnmanagedType.LPUTF8Str)] string dir_path);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr qt_version();

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr qt_last_error();

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_audio_free(ref qt_audio a);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_init_default_params(out qt_init_params p);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr qt_init(in qt_init_params params_init);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_free(IntPtr q);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern qt_status qt_extract_voice_ref(IntPtr q, IntPtr ref_audio_24k, int ref_n_samples, out qt_voice_ref out_ref);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_voice_ref_free(ref qt_voice_ref ref_voice);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_log_set(qt_log_cb cb, IntPtr user_data);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void qt_tts_default_params(out qt_tts_params p);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int qt_num_codebooks(IntPtr q);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern qt_status qt_synthesize(IntPtr q, in qt_tts_params params_tts, out qt_audio out_audio);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int qt_duration_sec_to_tokens(IntPtr q, float duration_sec);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int qt_n_speakers(IntPtr q);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr qt_speaker_name(IntPtr q, int i);
    }
}
