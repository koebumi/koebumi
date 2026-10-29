using System.Diagnostics;
using System.Windows;
using System.Windows.Threading;
using Koebumi.Core;

namespace Koebumi.App;

public partial class App : Application
{
    const string SingleInstanceName = "Koebumi.App.SingleInstance";
    /// 2 つ目を起動したときに、動いている 1 つ目に設定を開かせる合図
    const string ShowSettingsEventName = "Koebumi.App.ShowSettings";
    /// 起動の確認用: この秒数のあとに自分で終了する（トレイの「終了」を押さずに、終了までの流れを確かめる）
    const string ExitAfterVariable = "KOEBUMI_EXIT_AFTER_SECONDS";
    /// 起動の確認用: 設定・履歴などを、使う人の %APPDATA%\Koebumi ではなくこのフォルダに置く（初めて起動したときの流れを確かめる）
    const string DataDirVariable = "KOEBUMI_DATA_DIR";

    Mutex? singleInstance;
    EventWaitHandle? showSettingsSignal;
    RegisteredWaitHandle? showSettingsWait;
    AppServices? services;
    TrayIcon? tray;
    HotkeyManager? hotkeys;
    AudioRecorder? recorder;
    TextInserter? inserter;
    DictationController? dictation;
    VoiceBar? voiceBar;
    SettingsWindow? settingsWindow;
    ForegroundWatcher? foreground;
    DispatcherTimer? pruneTimer;
    DispatcherTimer? exitTimer;
    /// 前の前面の窓が、管理者として動くアプリだったか
    bool lastForegroundElevated;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += (_, args) => Debug.WriteLine($"[Koebumi] 想定外の例外: {args.Exception}");
        ScreenNameFixer.Reader = new JapanesePhoneticReader();

        if (e.Args.Contains("--selftest"))
        {
            // 常駐中の本体があっても動かせるよう、単一起動の確認もトレイも付けない
            _ = Task.Run(async () =>
            {
                var code = await new SelfTest(this).RunAsync();
                await Dispatcher.InvokeAsync(() => Shutdown(code));
            });
            return;
        }

        // 同時に 1 つだけ動かす。後から起動したほうは、動いているほうに設定を開かせて終わる
        // （トレイのアイコンは Windows 11 では「^」の中に隠れるので、見つからずにもう一度起動することがある）
        singleInstance = new Mutex(true, SingleInstanceName, out var isFirst);
        if (!isFirst)
        {
            singleInstance.Dispose();
            singleInstance = null;
            if (EventWaitHandle.TryOpenExisting(ShowSettingsEventName, out var signal))
            {
                using (signal) signal.Set();
            }
            Shutdown();
            return;
        }
        showSettingsSignal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSettingsEventName);
        showSettingsWait = ThreadPool.RegisterWaitForSingleObject(showSettingsSignal,
            (_, _) => Dispatcher.BeginInvoke(ShowSettings), null, Timeout.Infinite, executeOnlyOnce: false);

        if (Environment.GetEnvironmentVariable(DataDirVariable) is { Length: > 0 } dataDir) Storage.RootOverride = dataDir;
        services = new AppServices();
        tray = new TrayIcon();
        tray.SettingsRequested += ShowSettings;
        tray.ExitRequested += Shutdown;

        recorder = new AudioRecorder();
        inserter = new TextInserter();
        hotkeys = new HotkeyManager(Dispatcher);
        hotkeys.UpdateBindings(services.Settings.Current);
        // ショートカットを変えたら、すぐ効かせる
        services.Settings.Changed += settings => hotkeys.UpdateBindings(settings);
        // コントローラが、ショートカットのコマンドを受け取り、状態を HotkeyManager に返す
        dictation = new DictationController(services, Dispatcher, recorder, inserter, hotkeys);
        voiceBar = new VoiceBar(dictation, services.Settings);
        if (!hotkeys.Start())
        {
            tray.ShowNotification("Koebumi", T("ショートカットを使えません（キーボードのフックを付けられませんでした）", "Shortcuts are unavailable (couldn't install the keyboard hook)"));
        }

        foreground = new ForegroundWatcher();
        foreground.Changed += OnForegroundChanged;
        foreground.Start();

        // 保存期間を過ぎた履歴を消す（起動時と、そのあと 1 時間ごと）
        PruneHistory();
        pruneTimer = new DispatcherTimer(TimeSpan.FromHours(1), DispatcherPriority.Background, (_, _) => PruneHistory(), Dispatcher);
        pruneTimer.Start();

        // 音声認識か整形に要る API キーがまだないなら、はじめに設定を開く（キーがないと、話しても入力できない）
        if (NeedsSetup(services))
        {
            ShowSettings();
            tray.ShowNotification("Koebumi", T("API キーを設定すると使えます。Koebumi はタスクバーの「^」の中にあります", "Set an API key to start. Koebumi lives in the taskbar's ^ menu"));
        }

        if (double.TryParse(Environment.GetEnvironmentVariable(ExitAfterVariable), out var seconds) && seconds > 0)
        {
            exitTimer = new DispatcherTimer(TimeSpan.FromSeconds(seconds), DispatcherPriority.Normal, (_, _) => Shutdown(), Dispatcher);
            exitTimer.Start();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        exitTimer?.Stop();
        pruneTimer?.Stop();
        showSettingsWait?.Unregister(null);
        showSettingsSignal?.Dispose();
        foreground?.Dispose();
        // 先にフックを外して、これ以上コマンドが届かないようにする
        hotkeys?.Dispose();
        dictation?.Dispose();
        voiceBar?.Dispose();
        settingsWindow?.Shutdown();
        inserter?.Dispose();
        recorder?.Dispose();
        tray?.Dispose();
        if (singleInstance != null)
        {
            singleInstance.ReleaseMutex();
            singleInstance.Dispose();
        }
        base.OnExit(e);
    }

    /// トレイの「設定…」。窓は 1 つだけ作り、閉じても隠すだけにして使い回す
    void ShowSettings()
    {
        if (services == null || hotkeys == null) return;
        settingsWindow ??= new SettingsWindow(services, hotkeys);
        settingsWindow.Show();
    }

    /// 選んでいる音声認識か整形が API キーを要るのに、まだ保存していない
    static bool NeedsSetup(AppServices services)
    {
        var s = services.Settings.Current;
        bool Missing(string account) => string.IsNullOrEmpty(services.Secrets.Get(account));
        return (s.SttProvider.RequiresKey && Missing(s.SttProvider.KeyAccount))
            || (s.LlmKeyAccount is { } llm && Missing(llm));
    }

    void PruneHistory()
    {
        try
        {
            services?.History.Prune(services.Settings.Current.HistoryRetention);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] 履歴の整理に失敗: {e.Message}");
        }
    }

    /// 前面の窓が変わった。管理者として動くアプリが前面のあいだはキーの離しが届かないので、そこから戻ったときだけ押しているキーの記録を捨てる
    /// （ほかの窓への切り替えでも捨てると、押している間だけ録音するときに、離しても録音が止まらなくなる）
    void OnForegroundChanged(ForegroundApp app)
    {
        if (lastForegroundElevated && !app.IsElevatedAboveUs) hotkeys?.Reset();
        lastForegroundElevated = app.IsElevatedAboveUs;
        // 管理者として動くアプリが前面のあいだは、ショートカットも貼り付けも届かない。切り替わった時点で知らせる
        if (app.IsElevatedAboveUs) dictation?.NotifyElevatedForeground();
        Debug.WriteLine($"[Koebumi] 前面: {app.ExeName} 「{app.WindowTitle}」{(app.IsElevatedAboveUs ? " 管理者として動いている" : "")}");
    }
}
