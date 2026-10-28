using System.Diagnostics;
using System.Globalization;
using Koebumi.App;
using Koebumi.Core;

namespace Koebumi.Cli;

/// 最前面の入力欄と画面の文字列を読んで表示する。Mac 版の `--read-context` に当たる。
///   koebumi --read-context [--delay 3]   --delay の秒だけ待つ間に、読みたいアプリを最前面にする
/// 読み取りはアプリの SurroundingTextReader をそのまま使う。--masked と --app は移していない
static class ReadContextCommand
{
    public static async Task<int> RunAsync(Options o)
    {
        double delay = 0;
        if (o.Value("--delay") is { } text && (!double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out delay) || delay < 0))
            return Program.UsageError($"invalid value for --delay: {text} (use seconds, such as 3)");
        if (delay > 0) await Task.Delay(TimeSpan.FromSeconds(delay));

        var app = ForegroundProcessName();
        // アプリと同じく、UI のないスレッド（MTA）で読む
        var detail = await Task.Run(SurroundingTextReader.ReadDetailed);
        var s = detail.Text;
        var fields = new Fields
        {
            ["app"] = app,
            ["ms"] = (int)detail.Ms,
            ["before"] = s?.Before ?? "",
            ["after"] = s?.After ?? "",
            ["screen"] = s?.Screen ?? "",
            ["screen_after"] = s?.ScreenAfter ?? "",
            ["terms"] = s?.Terms ?? [],
            ["info"] = detail.Info,
        };
        // メールの返信先として読めたもの（宛名と、社外か社内か）
        if (s is not null && MailReply.Context(s) is { } reply)
        {
            fields["mail_reply"] = new Fields
            {
                ["addressee"] = reply.Addressee ?? "",
                ["external"] = reply.External is { } external ? (external ? "yes" : "no") : "unknown",
            };
        }
        Console.Out.WriteLine(JsonOutput.Pretty(fields));
        return s is null ? 1 : 0;
    }

    static string ForegroundProcessName()
    {
        try
        {
            var hwnd = Native.GetForegroundWindow();
            if (hwnd == IntPtr.Zero) return "?";
            Native.GetWindowThreadProcessId(hwnd, out var pid);
            return Process.GetProcessById((int)pid).ProcessName;
        }
        catch (Exception)
        {
            return "?";
        }
    }
}
