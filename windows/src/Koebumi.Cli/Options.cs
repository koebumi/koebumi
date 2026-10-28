using Koebumi.Core;

namespace Koebumi.Cli;

/// コマンドラインの引数。Mac 版の `value(flag)` と同じく、同じ指定が複数あれば最初のものを使う。
/// Mac 版は知らない指定を黙って捨てるが、ここでは誤りにする（打ち間違いで、意図しない設定のまま API を呼ばないため）
sealed class Options
{
    /// 値を取る指定
    static readonly HashSet<string> ValueFlags =
    [
        "--transcribe", "--polish", "--eval", "--mode", "--lang", "--target", "--category", "--app", "--selection", "--vocab",
        "--llm", "--stt", "--stt-model", "--stt-base-url", "--service", "--base-url", "--model", "--trials", "--delay",
    ];

    /// 値を取らない指定
    static readonly HashSet<string> SwitchFlags = ["--json", "--verbose", "--raw", "--read-context", "--help", "-h"];

    /// Mac 版にだけある指定（Windows 版には移していない）
    static readonly HashSet<string> MacOnly =
    [
        "--dir", "--ssh", "--stream", "--prewarm", "--screen", "--detect-agent", "--context-demo", "--answer-prompt",
        "--herdr-pane", "--focus-first", "--masked", "--stt-terms-test", "--terms",
    ];

    readonly Dictionary<string, string> values = new(StringComparer.Ordinal);
    readonly HashSet<string> switches = new(StringComparer.Ordinal);

    public string? Value(string flag) => values.GetValueOrDefault(flag);

    public bool Has(string flag) => switches.Contains(flag) || values.ContainsKey(flag);

    /// 解析できなければ null と、その理由を返す
    public static Options? Parse(IReadOnlyList<string> args, out string error)
    {
        var options = new Options();
        error = "";
        for (int i = 0; i < args.Count; i++)
        {
            var a = args[i];
            if (ValueFlags.Contains(a))
            {
                if (i + 1 >= args.Count)
                {
                    error = $"{a} needs a value";
                    return null;
                }
                options.values.TryAdd(a, args[++i]);
            }
            else if (SwitchFlags.Contains(a))
            {
                options.switches.Add(a);
            }
            else
            {
                error = MacOnly.Contains(a) ? $"{a} is a Mac-only option and is not available on Windows"
                    : a.StartsWith('-') ? $"unknown option: {a}"
                    : $"unexpected argument: {a} (quote the text if it contains spaces)";
                return null;
            }
        }
        return options;
    }

    /// 指定した列挙の値を取る。--llm のように指定がなければ null。指定が正しくなければ error に理由を入れる
    public T? Choice<T>(string flag, out string? error) where T : struct, Enum
    {
        error = null;
        if (Value(flag) is not { } raw) return null;
        foreach (var candidate in System.Enum.GetValues<T>())
        {
            if (string.Equals(Storage.Raw(candidate), raw, StringComparison.OrdinalIgnoreCase)) return candidate;
        }
        var allowed = string.Join("|", System.Enum.GetValues<T>().Select(c => Storage.Raw(c)));
        error = flag switch
        {
            "--llm" when raw is "appleOnDevice" or "claudeCode" or "codex" => $"--llm {raw} is not available on Windows (use {allowed})",
            "--stt" when raw is "apple" or "local" => $"--stt {raw} is not available on Windows (use {allowed})",
            _ => $"invalid value for {flag}: {raw} (use {allowed})",
        };
        return null;
    }
}
