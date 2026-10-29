using System.Text;

namespace Koebumi.Phase0;

/// 結果を画面とファイル（%TEMP%\koebumi-phase0\results-*.txt）に書く
static class Report
{
    public static readonly string File = Path.Combine(Targets.Dir, $"results-{DateTime.Now:yyyyMMdd-HHmmss}.txt");
    public static int Failures;

    public static void Line(string s)
    {
        Console.WriteLine(s);
        System.IO.File.AppendAllText(File, s + "\n", Encoding.UTF8);
    }

    public static void Head(string s) => Line($"\n== {s}");

    public static void Check(string item, bool ok, string detail = "")
    {
        if (!ok) Failures++;
        Line($"[{(ok ? "OK" : "NG")}] {item}{(detail.Length > 0 ? ": " + detail : "")}");
    }

    public static void Info(string item, string detail) => Line($"[--] {item}: {detail}");

    /// 改行の書き方（\r\n・\r・\v）の違いを除く
    public static string Lines(string? s) => (s ?? "").Replace("\r\n", "\n").Replace('\r', '\n').Replace('\v', '\n');

    public static string Show(string? s) => (s ?? "").Replace("\r\n", "⏎").Replace("\r", "⏎").Replace("\n", "⏎");
}
