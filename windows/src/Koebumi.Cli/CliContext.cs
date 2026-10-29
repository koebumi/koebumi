using Koebumi.App;
using Koebumi.Core;

namespace Koebumi.Cli;

/// 使う人の設定・辞書・文体と、--llm などの指定をまとめたもの。
/// 設定・履歴・統計は書き換えない。%APPDATA%\Koebumi がなければ作らず、既定の設定で動く
sealed class CliContext
{
    public required AppSettings Settings { get; init; }
    public required DictionaryStore Dictionary { get; init; }
    public required PersonalizationStore Personalization { get; init; }
    public required EnvFallbackSecretStore Secrets { get; init; }

    /// 指定が正しくなければ null と、その理由を返す
    public static CliContext? Load(Options options, out string error)
    {
        error = "";
        // Storage.Root は呼ぶだけでフォルダを作るので使わない。ファイルがあるときだけ読む
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Koebumi");
        var settings = Storage.LoadAt<AppSettings>(Path.Combine(root, AppSettings.FileName)) ?? new AppSettings();
        L10n.Current = settings.UiLanguage;

        var llm = options.Choice<LLMProvider>("--llm", out var e1);
        var stt = options.Choice<STTProvider>("--stt", out var e2);
        var service = options.Choice<CompatService>("--service", out var e3);
        if ((e1 ?? e2 ?? e3) is { } problem)
        {
            error = problem;
            return null;
        }
        if (llm is { } l) settings.LlmProvider = l;
        if (stt is { } s) settings.SttProvider = s;
        if (options.Value("--stt-base-url") is { } sttUrl) settings.SttBaseURLs[Storage.Raw(settings.SttProvider)] = sttUrl;
        if (options.Value("--stt-model") is { } sttModel) settings.SttModels[Storage.Raw(settings.SttProvider)] = sttModel;
        if (service is { } c) settings.CompatService = c;
        if (options.Value("--base-url") is { } url) settings.CompatBaseURLs[Storage.Raw(settings.CompatService)] = url;
        if (options.Value("--model") is { } model)
        {
            settings.ClaudeModel = model;
            settings.CompatModels[Storage.Raw(settings.CompatService)] = model;
        }

        return new CliContext
        {
            Settings = settings,
            // 辞書と文体の学習は、ファイルがあるときだけ読む（コンストラクターがフォルダを作るため）
            Dictionary = File.Exists(Path.Combine(root, DictionaryStore.FileName)) ? new DictionaryStore(root) : new DictionaryStore(inMemory: true),
            Personalization = File.Exists(Path.Combine(root, PersonalizationStore.FileName)) ? new PersonalizationStore(root) : new PersonalizationStore(inMemory: true),
            Secrets = new EnvFallbackSecretStore(new CredentialStore()),
        };
    }

    /// 整形しない設定なら null
    public ILLMEngine? MakeEngine() => LLMFactory.Make(Settings, Secrets);

    public ITranscriber MakeTranscriber() => TranscriberFactory.Make(Settings, Secrets);

    public string LlmTitle => Settings.LlmProvider == LLMProvider.Claude ? Settings.LlmProvider.Title : Settings.CompatService.Title;

    /// --verbose: どのキーを使うかを標準エラーに出す（値は出さない）
    public void DescribeKeys(bool transcribe)
    {
        if (Settings.LlmKeyAccount is { } account) Console.Error.WriteLine($"key for {LlmTitle}: {Secrets.Source(account)}");
        if (transcribe && Settings.SttProvider.RequiresKey)
            Console.Error.WriteLine($"key for {Settings.SttProvider.Title} speech recognition: {Secrets.Source(Settings.SttProvider.KeyAccount)}");
    }
}
