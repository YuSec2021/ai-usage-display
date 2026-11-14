using System.Diagnostics;

namespace AIUsage.Windows;

internal static class WindowsPaths
{
    public static ProcessStartInfo? Codex()
    {
        var directories = (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
            .Concat(new[] { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "npm"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin") });
        foreach (var directory in directories.Where(Directory.Exists))
            foreach (var name in new[] { "codex.exe", "codex.cmd" })
            {
                var path = Path.GetFullPath(Path.Combine(directory, name));
                if (!File.Exists(path)) continue;
                if (name.EndsWith(".exe"))
                {
                    var info = new ProcessStartInfo(path); info.ArgumentList.Add("app-server"); return info;
                }
                // cmd.exe expands metacharacters even inside some quoting forms.
                if (path.IndexOfAny(['%', '!', '&', '|', '<', '>', '^', '\r', '\n']) >= 0) continue;
                return new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"),
                    $"/d /s /c \"\"{path}\" app-server\"");
            }
        return null;
    }
    public static string? FindBash()
    {
        var configured = Environment.GetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH");
        var paths = new[] { configured,
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "bin", "bash.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Git", "bin", "bash.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Git", "bin", "bash.exe") }
            .Concat((Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator)
                .Where(directory => !string.IsNullOrWhiteSpace(directory) && directory.Contains("Git", StringComparison.OrdinalIgnoreCase))
                .SelectMany(directory => new[] { Path.Combine(directory, "bash.exe"), Path.GetFullPath(Path.Combine(directory, "..", "bin", "bash.exe")) }));
        return paths.FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path));
    }
}
