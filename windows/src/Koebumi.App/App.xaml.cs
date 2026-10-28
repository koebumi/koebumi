using System.Diagnostics;
using System.Windows;
using Koebumi.Core;

namespace Koebumi.App;

public partial class App : Application
{
    const string SingleInstanceName = "Koebumi.App.SingleInstance";

    Mutex? singleInstance;
    TrayIcon? tray;
    HotkeyManager? hotkeys;
    ForegroundWatcher? foreground;

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

        // 同時に 1 つだけ動かす。後から起動したほうは、何も出さずに終わる
        singleInstance = new Mutex(true, SingleInstanceName, out var isFirst);
        if (!isFirst)
        {
            singleInstance.Dispose();
            singleInstance = null;
            Shutdown();
            return;
        }

        var settings = Storage.Load<AppSettings>(AppSettings.FileName) ?? new AppSettings();

        tray = new TrayIcon();
        tray.SettingsRequested += () => Debug.WriteLine("[Koebumi] 設定（まだない）");
        tray.ExitRequested += Shutdown;

        hotkeys = new HotkeyManager(Dispatcher);
        hotkeys.UpdateBindings(settings);
        hotkeys.CommandReceived += OnCommand;
        if (!hotkeys.Start()) tray.ShowNotification("Koebumi", "ショートカットを使えません（キーボードのフックを付けられませんでした）");

        foreground = new ForegroundWatcher();
        foreground.Changed += OnForegroundChanged;
        foreground.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        foreground?.Dispose();
        hotkeys?.Dispose();
        tray?.Dispose();
        if (singleInstance != null)
        {
            singleInstance.ReleaseMutex();
            singleInstance.Dispose();
        }
        base.OnExit(e);
    }

    /// 前面の窓が変わった。管理者として動くアプリが前面のあいだはキーの離しが届かないので、押しているキーの記録を捨てる
    void OnForegroundChanged(ForegroundApp app)
    {
        hotkeys?.Reset();
        Debug.WriteLine($"[Koebumi] 前面: {app.ExeName} 「{app.WindowTitle}」{(app.IsElevatedAboveUs ? " 管理者として動いている" : "")}");
    }

    /// 録音の流れをつなぐまでの仮の処理。コマンドを Debug に書き、コントローラの代わりに状態を返す
    void OnCommand(HotkeyCommand command)
    {
        Debug.WriteLine($"[Koebumi] コマンド: {command}");
        switch (command.Kind)
        {
            case HotkeyCommandKind.Begin or HotkeyCommandKind.SwitchMode:
                hotkeys?.SetState(EngineState.Recording(command.Mode));
                break;
            case HotkeyCommandKind.Finish:
                hotkeys?.SetState(EngineState.Busy);
                _ = Task.Delay(300).ContinueWith(_ => hotkeys?.SetState(EngineState.Idle), TaskScheduler.FromCurrentSynchronizationContext());
                break;
            case HotkeyCommandKind.Cancel or HotkeyCommandKind.Abort:
                hotkeys?.SetState(EngineState.Idle);
                break;
        }
    }
}
