using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace AIUsage.Windows;

internal static class Credentials
{
    private const string Target = "AIUsage/KimiCode";
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags, Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public uint BlobSize;
        public nint Blob;
        public uint Persist, AttributeCount;
        public nint Attributes;
        public string? Alias;
        public string UserName;
    }
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredWriteW(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredReadW(string target, uint type, uint flags, out nint credential);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)] private static extern bool CredDeleteW(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(nint value);

    public static string? Read()
    {
        var environment = Environment.GetEnvironmentVariable("KIMI_API_KEY");
        if (!string.IsNullOrWhiteSpace(environment)) return environment.Trim();
        if (!CredReadW(Target, 1, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.BlobSize is 0 or > 2560 || credential.BlobSize % 2 != 0) return null;
            return Marshal.PtrToStringUni(credential.Blob, checked((int)credential.BlobSize / 2));
        }
        finally { CredFree(pointer); }
    }
    public static void Save(string key)
    {
        key = key.Trim();
        var bytes = Encoding.Unicode.GetBytes(key);
        if (bytes.Length is 0 or > 2560 || key.Any(char.IsControl)) throw new InvalidDataException("API Key 为空、含控制字符或长度不受支持");
        var pointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            var credential = new Credential { Type = 1, TargetName = Target, UserName = "api-key", Persist = 2,
                BlobSize = (uint)bytes.Length, Blob = pointer };
            if (!CredWriteW(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error(), "无法保存 Windows 凭证");
        }
        finally
        {
            Array.Clear(bytes);
            for (var index = 0; index < key.Length * 2; index++) Marshal.WriteByte(pointer, index, 0);
            Marshal.FreeHGlobal(pointer);
        }
    }
    public static void Remove()
    {
        if (!CredDeleteW(Target, 1, 0) && Marshal.GetLastWin32Error() != 1168)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "无法删除 Windows 凭证");
    }
}
