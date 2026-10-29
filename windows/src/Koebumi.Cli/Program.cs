using System.Text;
using Koebumi.App;
using Koebumi.Core;

namespace Koebumi.Cli;

/// Koebumi の開発用コマンド。録音・貼り付け・画面は使わず、認識と整形の結果だけを標準出力に出す。
/// 設定・履歴・統計は保存しない（使う人の %APPDATA%\Koebumi は読むだけで、なければ作らない）
static class Program
{
    const string Usage = """
        usage: koebumi (--transcribe <file> | --polish <text>) [--mode dictate|translate|ask] [--lang ja-JP] [--target en-US]
                       [--category email|chat|document|code|ai|other] [--app Name] [--selection TEXT]
                       [--vocab "Term=heard|heard2,Term2~heard3"] [--json] [--verbose]
                       [--llm claude|openAICompatible|none] [--stt openai|groq|custom] [--stt-model NAME] [--stt-base-url URL]
                       [--service openai|groq|openrouter|gemini|ollama|lmstudio|custom] [--base-url URL] [--model NAME]
               koebumi --eval <cases.json> [--trials N] [--llm …] [--service …] [--base-url URL] [--model NAME] [--json] [--raw] [--verbose]
               koebumi --read-context [--delay SECONDS]
        """;

    const string Notes = """

        Settings and the dictionary are read from %APPDATA%\Koebumi (if it exists) and then overridden by the options above.
        Nothing is saved. --vocab replaces the dictionary for this run: "=" replaces what was heard, "~" only hints the AI.

        API keys are looked up in Windows Credential Manager (the same accounts as the app, "Koebumi/<account>"),
        and if there is none, in the environment variable for the service:
          openai: OPENAI_API_KEY   groq: GROQ_API_KEY   anthropic (--llm claude): ANTHROPIC_API_KEY
          openrouter: OPENROUTER_API_KEY   gemini: GEMINI_API_KEY
        Ollama, LM Studio and custom servers need no key. Keys are never printed (--verbose shows only where a key was found).

        --transcribe reads 16-bit PCM WAV directly; other WAV formats, mp3, m4a, flac and so on are decoded by Windows Media Foundation.
        With --lang, only that language is sent to the speech recognition; without it, all the dictation languages in the settings are.

        Not available on Windows: the Apple, local-model, Claude Code and Codex engines, and --dir, --ssh, --stream, --prewarm,
        --detect-agent, --context-demo, --answer-prompt.
        """;

    static async Task<int> Main(string[] args)
    {
        SetUpConsole();
        try
        {
            // 名前の読み。アプリと同じ実装を入れる
            ScreenNameFixer.Reader = new JapanesePhoneticReader();

            if (Options.Parse(args, out var error) is not { } options) return UsageError(error);
            if (options.Has("--help") || options.Has("-h"))
            {
                Console.Out.WriteLine(Usage + "\n" + Notes);
                return 0;
            }
            if (options.Has("--read-context")) return await ReadContextCommand.RunAsync(options);

            var evalPath = options.Value("--eval");
            if (evalPath is null && options.Value("--transcribe") is null && options.Value("--polish") is null) return UsageError("");
            if (CliContext.Load(options, out var problem) is not { } context) return UsageError(problem);
            return evalPath is not null
                ? await EvalCommand.RunAsync(options, context, evalPath)
                : await PolishCommand.RunAsync(options, context);
        }
        catch (Exception e)
        {
            Console.Out.WriteLine($"ERROR: {Message(e)}");
            return 1;
        }
    }

    /// 指定が正しくないとき。使い方を出して終わる（終了コード 2）
    public static int UsageError(string message)
    {
        if (message.Length > 0) Console.Error.WriteLine($"error: {message} (koebumi --help for usage)");
        else
        {
            Console.Error.WriteLine(Usage);
            Console.Error.WriteLine("(koebumi --help for details)");
        }
        return 2;
    }

    public static string Message(Exception e) =>
        e is HttpRequestException { InnerException: { } inner } ? $"{e.Message} ({inner.Message})" : e.Message;

    /// 日本語が Windows Terminal・Git Bash・パイプのどれでも化けないよう、UTF-8（BOM なし）と LF で出す
    static void SetUpConsole()
    {
        var utf8 = new UTF8Encoding(false);
        // コンソールがつながっていないとき（リダイレクト）は設定できないが、それでよい
        try { Console.OutputEncoding = utf8; }
        catch (IOException) { }
        Console.SetOut(new StreamWriter(Console.OpenStandardOutput(), utf8) { AutoFlush = true, NewLine = "\n" });
        Console.SetError(new StreamWriter(Console.OpenStandardError(), utf8) { AutoFlush = true, NewLine = "\n" });
    }
}
