using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Cli;

/// 日本語の表記・敬語・画面の文脈の効果を、実際のモデルで確かめる。Mac 版の Eval.run に当たる。
///   koebumi --eval cases.json [--trials 3] [--llm …] [--json]   変更前の設定と比べて採点する
/// 事例の形と採点、報告の形は Mac 版と同じ（eval/results-*.json と比べられる）
static class EvalCommand
{
    /// 1 つの事例。eval/ja-cases.json の形
    sealed class Case
    {
        public required string Id { get; init; }
        public required string Transcript { get; init; }
        public AppCategory Category { get; init; } = AppCategory.Other;
        public StylePreset Preset { get; init; } = StylePreset.Auto;
        public string Language { get; init; } = "ja-JP";
        public JapaneseNotation? Notation { get; init; }
        public ChatPunctuation ChatPunctuation { get; init; } = ChatPunctuation.Keep;
        public string Before { get; init; } = "";
        public string After { get; init; } = "";
        public string Screen { get; init; } = "";
        /// すべて含む
        public List<string> Expect { get; init; } = [];
        /// 各グループのどれか 1 つを含む
        public List<List<string>> ExpectAny { get; init; } = [];
        /// どれも含まない
        public List<string> Forbid { get; init; } = [];
        /// この文字列で終わらない
        public List<string> ForbidSuffix { get; init; } = [];
        public string? ExpectPrefix { get; init; }

        /// 採点で外れた項目（空なら合格）。Swift の文字列の比べ方に合わせて、正規化（NFC）してから比べる
        public List<string> Failures(string output)
        {
            var failures = new List<string>();
            var text = Nfc(output);
            foreach (var e in Expect)
            {
                if (!text.Contains(Nfc(e), StringComparison.Ordinal)) failures.Add($"missing {e}");
            }
            foreach (var group in ExpectAny)
            {
                if (!group.Any(e => text.Contains(Nfc(e), StringComparison.Ordinal))) failures.Add($"missing one of {string.Join("|", group)}");
            }
            foreach (var e in Forbid)
            {
                if (text.Contains(Nfc(e), StringComparison.Ordinal)) failures.Add($"contains {e}");
            }
            var trimmed = text.Trim();
            foreach (var e in ForbidSuffix)
            {
                if (trimmed.EndsWith(Nfc(e), StringComparison.Ordinal)) failures.Add($"ends with {e}");
            }
            if (ExpectPrefix is { } prefix && !text.StartsWith(Nfc(prefix), StringComparison.Ordinal))
                failures.Add($"does not start with \"{prefix}\"");
            return failures;
        }

        static string Nfc(string s) => s.Normalize(NormalizationForm.FormC);
    }

    public static async Task<int> RunAsync(Options o, CliContext ctx, string path)
    {
        byte[] data;
        try { data = File.ReadAllBytes(path); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"ERROR: cannot read {path}: {e.Message}");
            return 2;
        }
        List<Case> cases;
        try { cases = JsonSerializer.Deserialize<List<Case>>(data, Storage.Json) ?? []; }
        catch (JsonException e)
        {
            Console.Out.WriteLine($"ERROR: {e.Message}");
            return 2;
        }
        int trials = 1;
        if (o.Value("--trials") is { } t && (!int.TryParse(t, out trials) || trials < 1))
            return Program.UsageError($"invalid value for --trials: {t} (use a number of 1 or more)");

        var settings = ctx.Settings;
        // 事例ごとの比較に、Claude の Web 検索は使わない（Ask のためのもの）
        settings.WebSearch = false;
        var engine = ctx.MakeEngine();
        Polisher.Verbose = o.Has("--verbose");
        if (Polisher.Verbose) ctx.DescribeKeys(transcribe: false);
        // キーがないと、すべての事例が AI なしの簡易整形になり、点数に意味がなくなる
        if (ctx.LlmKeyAccount is { } account && ctx.Secrets.Get(account) is null)
        {
            Console.Error.WriteLine("ERROR: " + T($"{ctx.LlmTitle} の API キーが見つかりません。", $"No API key for {ctx.LlmTitle}.")
                + " " + $"(Credential Manager account \"Koebumi/{account}\" or the environment variable; see --help)");
            return 1;
        }

        var json = o.Has("--json");
        var showRaw = o.Has("--raw");
        int beforePass = 0, afterPass = 0, runs = 0;
        var rows = new List<Fields>();
        foreach (var c in cases)
        {
            for (int trial = 1; trial <= trials; trial++)
            {
                // 変更前: 表記ルール・画面の文脈なし。敬語は以前の「フォーマル」の指示
                var oldStyle = c.Preset == StylePreset.Auto
                    ? c.Category.DefaultStyleDescription
                    : c.Category.DefaultStyleDescription + " Formal and polite register (in Japanese: 丁寧語/敬語).";
                var baseline = MakeRequest(c.Transcript, c.Category, StylePreset.Auto, null, null, false) with
                {
                    StyleDescription = oldStyle,
                    SourceLanguages = [c.Language],
                };
                var improved = MakeRequest(c.Transcript, c.Category, c.Preset, c.Notation ?? new JapaneseNotation(),
                    new SurroundingText { Before = c.Before, After = c.After, Screen = c.Screen }, true) with
                {
                    SourceLanguages = [c.Language],
                    ChatPunctuation = c.ChatPunctuation,
                    AllowsRewording = c.Preset != StylePreset.Auto,
                };
                var clock = Stopwatch.StartNew();
                var b = await TextOrError(baseline, engine);
                var beforeMs = (int)clock.ElapsedMilliseconds;
                clock.Restart();
                var a = await TextOrError(improved, engine);
                var afterMs = (int)clock.ElapsedMilliseconds;
                if (showRaw && engine is not null)
                {
                    // AI の出力そのもの（OutputGuard と表記の統一の前）
                    var source = Polisher.Prepare(improved.Transcript, new Dictionary<string, string>());
                    string raw;
                    try { raw = await engine.PolishAsync(improved with { Transcript = source }); }
                    catch (Exception) { raw = "ERROR"; }
                    Console.Out.WriteLine($"  raw:    {raw.Replace("\n", "⏎")}  guard={OutputGuard.Accepts(source, raw).ToString().ToLowerInvariant()}");
                }
                var failuresBefore = c.Failures(b);
                var failuresAfter = c.Failures(a);
                runs++;
                if (failuresBefore.Count == 0) beforePass++;
                if (failuresAfter.Count == 0) afterPass++;
                rows.Add(new Fields
                {
                    ["id"] = c.Id,
                    ["trial"] = trial,
                    ["before"] = b,
                    ["after"] = a,
                    ["before_ok"] = failuresBefore.Count == 0,
                    ["after_ok"] = failuresAfter.Count == 0,
                    ["before_fail"] = failuresBefore,
                    ["after_fail"] = failuresAfter,
                    ["before_ms"] = beforeMs,
                    ["after_ms"] = afterMs,
                });
                if (!json)
                {
                    Console.Out.WriteLine($"[{c.Id} #{trial}] before {Verdict(failuresBefore)} | after {Verdict(failuresAfter)} ({afterMs} ms)");
                    Console.Out.WriteLine($"  before: {b.Replace("\n", "⏎")}" + (failuresBefore.Count == 0 ? "" : $"  ← {string.Join(", ", failuresBefore)}"));
                    Console.Out.WriteLine($"  after:  {a.Replace("\n", "⏎")}" + (failuresAfter.Count == 0 ? "" : $"  ← {string.Join(", ", failuresAfter)}"));
                }
            }
        }
        var name = engine?.Name ?? "basic";
        if (json)
        {
            Console.Out.WriteLine(JsonOutput.Pretty(new Fields
            {
                ["engine"] = name,
                ["runs"] = runs,
                ["before_pass"] = beforePass,
                ["after_pass"] = afterPass,
                ["rows"] = rows,
            }));
        }
        else
        {
            Console.Out.WriteLine($"\nengine: {name}  runs: {runs}  before: {beforePass}/{runs} pass  after: {afterPass}/{runs} pass");
        }
        return 0;
    }

    static string Verdict(List<string> failures) => failures.Count == 0 ? "PASS" : "FAIL";

    /// 整形に失敗したときも、事例は止めずに "ERROR" として採点する
    static async Task<string> TextOrError(PolishRequest request, ILLMEngine? engine)
    {
        try { return (await Polisher.Run(request, engine)).Text; }
        catch (Exception) { return "ERROR"; }
    }

    static PolishRequest MakeRequest(string transcript, AppCategory category, StylePreset preset, JapaneseNotation? notation,
        SurroundingText? surrounding, bool inPrompt) => new()
    {
        Transcript = transcript,
        Mode = Mode.Dictate,
        SourceLanguages = ["ja-JP"],
        TargetLanguage = null,
        AppName = category.Title,
        Category = category,
        StyleDescription = preset.StyleDescription(category),
        PersonalStyle = null,
        Vocabulary = [],
        Corrections = [],
        Notation = notation,
        Surrounding = surrounding,
        SurroundingInPrompt = inPrompt,
        MailReply = category == AppCategory.Email && surrounding is not null ? MailReply.Context(surrounding) : null,
    };
}
