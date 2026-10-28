using Koebumi.Core;

namespace Koebumi.App;

/// 設定。変えるときは Update を通す（写しを変えて、違っていたら保存して Changed を出す）。UI スレッドから使う
public sealed class SettingsStore
{
    public AppSettings Current { get; private set; }

    /// 設定が変わった（UI スレッドで呼ばれる）
    public event Action<AppSettings>? Changed;

    public SettingsStore()
    {
        Current = Storage.Load<AppSettings>(AppSettings.FileName) ?? new AppSettings();
        L10n.Current = Current.UiLanguage;
    }

    public void Update(Action<AppSettings> change)
    {
        var copy = Current.Clone();
        change(copy);
        if (copy.SameAs(Current)) return;
        Current = copy;
        L10n.Current = copy.UiLanguage;
        Storage.Save(copy, AppSettings.FileName);
        Changed?.Invoke(copy);
    }
}

/// アプリ全体で 1 つずつ持つもの（設定・API キー・辞書・履歴・統計・文体の学習）。App が起動時に作る
public sealed class AppServices
{
    public SettingsStore Settings { get; } = new();
    public ISecretStore Secrets { get; } = new CredentialStore();
    public DictionaryStore Dictionary { get; } = new();
    public HistoryStore History { get; } = new();
    public StatsStore Stats { get; } = new();
    public PersonalizationStore Personalization { get; } = new();
}
