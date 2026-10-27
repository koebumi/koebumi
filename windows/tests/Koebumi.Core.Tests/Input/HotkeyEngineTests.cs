using Koebumi.Core;

namespace Koebumi.Core.Tests;

/// 低レベルのキーボードフックに届く仮想キーコード（修飾キーは左右を区別したもの）
file static class Vk
{
    public const int LCtrl = 0xA2, RCtrl = 0xA3, LShift = 0xA0, LAlt = 0xA4, LWin = 0x5B, RWin = 0x5C;
    public const int Left = 0x25, E = 0x45;
}

/// テスト用の時計を進められる HotkeyEngine
file sealed class Harness
{
    public readonly HotkeyEngine Engine = new();
    public DateTime Clock = DateTime.UnixEpoch.AddSeconds(1000);
    public EngineState State = EngineState.Idle;

    public Harness()
    {
        Engine.Bindings = [(Mode.Dictate, Shortcut.CtrlWin), (Mode.Translate, Shortcut.CtrlWinShift), (Mode.Ask, Shortcut.CtrlWinSpace)];
        Engine.PasteBindings = [Shortcut.CtrlAltV];
        Engine.RevertBindings = [Shortcut.CtrlAltZ];
        Engine.Now = () => Clock;
    }

    public HotkeyResult Send(HotkeyEvent e)
    {
        var r = Engine.Handle(e, State);
        foreach (var c in r.Commands)
        {
            switch (c.Kind)
            {
                case HotkeyCommandKind.Begin or HotkeyCommandKind.SwitchMode: State = EngineState.Recording(c.Mode); break;
                case HotkeyCommandKind.Finish: State = EngineState.Busy; break;
                case HotkeyCommandKind.Cancel or HotkeyCommandKind.Abort: State = EngineState.Idle; break;
            }
        }
        return r;
    }

    public HotkeyResult Down(int vk) => Send(HotkeyEvent.KeyDown(vk));
    public HotkeyResult Up(int vk) => Send(HotkeyEvent.KeyUp(vk));

    /// Ctrl、Win の順に押す（Mac 版の Fn の押下）。Win の押下の結果を返す
    public HotkeyResult PressCtrlWin()
    {
        Assert.Empty(Down(Vk.LCtrl).Commands);
        return Down(Vk.LWin);
    }

    /// Win、Ctrl の順に離す（Mac 版の Fn の離し）。Ctrl の離しの結果を返す
    public HotkeyResult ReleaseCtrlWin()
    {
        Assert.Empty(Up(Vk.LWin).Commands);
        return Up(Vk.LCtrl);
    }

    public void Wait(double s) => Clock += TimeSpan.FromSeconds(s);
}

// Mac 版の HotkeyEngineTests。Fn → Ctrl+Win、Fn + Left ⇧ → Ctrl+Win+Shift、Fn + Space → Ctrl+Win+Space、⌘⌥V → Ctrl+Alt+V、⌘⌥Z → Ctrl+Alt+Z
public class HotkeyEngineTests
{
    [Fact]
    public void TapStartsHandsFreeAndSecondTapFinishes()
    {
        var h = new Harness();
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.PressCtrlWin().Commands);
        h.Wait(0.1);
        Assert.Empty(h.ReleaseCtrlWin().Commands);  // 短く押しただけ → ハンズフリーで録音継続
        h.Wait(3);
        Assert.Empty(h.PressCtrlWin().Commands);  // 録音中の押下は離した時点で判定
        Assert.Equal([HotkeyCommand.Finish], h.ReleaseCtrlWin().Commands);
    }

    [Fact]
    public void HoldIsPushToTalk()
    {
        var h = new Harness();
        h.PressCtrlWin();
        h.Wait(2);
        Assert.Equal([HotkeyCommand.Finish], h.ReleaseCtrlWin().Commands);
    }

    [Fact]
    public void AddingShiftSwitchesToTranslate()
    {
        var h = new Harness();
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.PressCtrlWin().Commands);
        var shift = h.Down(Vk.LShift);
        Assert.Equal([HotkeyCommand.SwitchMode(Mode.Translate)], shift.Commands);
        Assert.False(shift.Swallow);  // Shift は入力先に届ける
        h.Wait(0.2);
        Assert.Empty(h.Up(Vk.LShift).Commands);
        Assert.Empty(h.ReleaseCtrlWin().Commands);  // 翻訳は押して離すとハンズフリー
        Assert.Equal(EngineState.Recording(Mode.Translate), h.State);
        // Ctrl+Win を押して確定
        h.PressCtrlWin();
        Assert.Equal([HotkeyCommand.Finish], h.ReleaseCtrlWin().Commands);
    }

    // Mac 版の fnSpaceStartsAskAndSwallowsSpace
    [Fact]
    public void CtrlWinSpaceStartsAskAndSwallowsSpace()
    {
        var h = new Harness();
        h.PressCtrlWin();
        var down = h.Down(KeyNames.Space);
        Assert.Equal([HotkeyCommand.SwitchMode(Mode.Ask)], down.Commands);
        Assert.True(down.Swallow);
        Assert.True(h.Down(KeyNames.Space).Swallow);  // オートリピート
        Assert.True(h.Up(KeyNames.Space).Swallow);
        h.ReleaseCtrlWin();
        Assert.Equal(EngineState.Recording(Mode.Ask), h.State);
    }

    // Mac 版の fnWithArrowAbortsSilently
    [Fact]
    public void CtrlWinWithArrowAbortsSilently()
    {
        var h = new Harness();
        h.PressCtrlWin();
        var r = h.Down(Vk.Left);
        Assert.Equal([HotkeyCommand.Abort], r.Commands);
        Assert.False(r.Swallow);
        Assert.False(h.Up(Vk.Left).Swallow);
        Assert.Empty(h.ReleaseCtrlWin().Commands);
    }

    [Fact]
    public void EscapeCancelsWhileRecordingOnly()
    {
        var h = new Harness();
        Assert.False(h.Down(KeyNames.Escape).Swallow);
        Assert.False(h.Up(KeyNames.Escape).Swallow);
        h.PressCtrlWin();
        h.ReleaseCtrlWin();
        var r = h.Down(KeyNames.Escape);
        Assert.Equal([HotkeyCommand.Cancel], r.Commands);
        Assert.True(r.Swallow);
        Assert.True(h.Up(KeyNames.Escape).Swallow);  // keyUp も入力先に届けない
    }

    [Fact]
    public void PressingTranslateWhileDictatingSwitchesOnRelease()
    {
        var h = new Harness();
        h.PressCtrlWin();
        h.ReleaseCtrlWin();
        h.Wait(2);
        h.PressCtrlWin();
        h.Down(Vk.LShift);
        h.Up(Vk.LShift);
        Assert.Equal([HotkeyCommand.SwitchMode(Mode.Translate)], h.ReleaseCtrlWin().Commands);
    }

    [Fact]
    public void IgnoresShortcutsWhileBusy()
    {
        var h = new Harness { State = EngineState.Busy };
        Assert.Empty(h.PressCtrlWin().Commands);
        Assert.Empty(h.ReleaseCtrlWin().Commands);
    }

    // Mac 版の commandOptionVPastesAfterAllKeysAreReleased
    [Fact]
    public void CtrlAltVPastesAfterAllKeysAreReleased()
    {
        var h = new Harness();
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        var down = h.Down(KeyNames.VKey);
        Assert.Empty(down.Commands);
        Assert.True(down.Swallow);  // 入力先のアプリには Ctrl+Alt+V を届けない
        Assert.True(h.Up(KeyNames.VKey).Swallow);
        Assert.Empty(h.Up(Vk.LAlt).Commands);
        Assert.Equal([HotkeyCommand.PasteLast], h.Up(Vk.LCtrl).Commands);
        Assert.Equal(EngineState.Idle, h.State);
    }

    // Mac 版の commandOptionZRevertsAfterAllKeysAreReleased
    [Fact]
    public void CtrlAltZRevertsAfterAllKeysAreReleased()
    {
        var h = new Harness();
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        var down = h.Down(KeyNames.ZKey);
        Assert.Empty(down.Commands);
        Assert.True(down.Swallow);
        h.Up(KeyNames.ZKey);
        h.Up(Vk.LAlt);
        Assert.Equal([HotkeyCommand.RevertLast], h.Up(Vk.LCtrl).Commands);
        // Ctrl+Z（入力先のアプリの取り消し）はそのまま届ける
        h.Down(Vk.LCtrl);
        Assert.False(h.Down(KeyNames.ZKey).Swallow);
        h.Up(KeyNames.ZKey);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
    }

    // Mac 版の pasteWithFnDiscardsTheRecordingItStarted
    [Fact]
    public void PasteWithCtrlWinDiscardsTheRecordingItStarted()
    {
        var h = new Harness();
        h.Engine.PasteBindings = [new Shortcut([ModKey.Control, ModKey.Win], KeyNames.VKey)];
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.PressCtrlWin().Commands);
        var down = h.Down(KeyNames.VKey);
        Assert.Equal([HotkeyCommand.Abort], down.Commands);
        Assert.True(down.Swallow);
        Assert.Empty(h.ReleaseCtrlWin().Commands);
        Assert.Equal([HotkeyCommand.PasteLast], h.Up(KeyNames.VKey).Commands);
    }

    [Fact]
    public void PasteShortcutIsPassedThroughWhileRecording()
    {
        var h = new Harness();
        h.PressCtrlWin();
        h.ReleaseCtrlWin();  // ハンズフリーで録音中
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        var down = h.Down(KeyNames.VKey);
        Assert.Empty(down.Commands);
        Assert.False(down.Swallow);
        h.Up(KeyNames.VKey);
        Assert.False(h.Up(Vk.LAlt).MaskBeforeRelease);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        Assert.Equal(EngineState.Recording(Mode.Dictate), h.State);
    }

    // Mac 版の modifierFlagsDecodeLeftAndRight
    [Fact]
    public void ModifierKeysDecodeLeftAndRight()
    {
        Assert.Equal(ModKey.LeftShift, ModKeys.FromVirtualKey(0xA0));
        Assert.Equal(ModKey.RightAlt, ModKeys.FromVirtualKey(0xA5));
        Assert.Equal(ModKey.RightControl, ModKeys.FromVirtualKey(0xA3));
        Assert.Equal(ModKey.RightWin, ModKeys.FromVirtualKey(0x5C));
        Assert.Equal(ModKey.LeftControl, ModKeys.FromVirtualKey(0x11));  // 左右を区別しないコードは左
        Assert.Null(ModKeys.FromVirtualKey(KeyNames.Space));
        Assert.Equal(0xA3, ModKey.RightControl.VirtualKey);
        Assert.Null(ModKey.Control.VirtualKey);
        Assert.Equal("Ctrl + Win + Space", Shortcut.CtrlWinSpace.Display);
        Assert.Equal("Ctrl + Left Shift + Win", new Shortcut([ModKey.Control, ModKey.Win, ModKey.LeftShift]).Display);
        Assert.Equal("Ctrl + Alt + V", Shortcut.CtrlAltV.Display);
        Assert.Equal("Right Ctrl", new Shortcut([ModKey.RightControl]).Display);
        var nonConvert = new Shortcut([], KeyNames.NonConvert).Display;
        Assert.True(nonConvert is "無変換" or "Muhenkan", nonConvert);
    }

    // ここから Windows 版で足したテスト

    [Fact]
    public void KeyNamesForWindowsKeys()
    {
        Assert.Equal("A", KeyNames.Name(0x41));
        Assert.Equal("Z", KeyNames.Name(KeyNames.ZKey));
        Assert.Equal("0", KeyNames.Name(0x30));
        Assert.Equal("F1", KeyNames.Name(0x70));
        Assert.Equal("F24", KeyNames.Name(0x87));
        Assert.Equal("Num 5", KeyNames.Name(0x65));
        Assert.Equal("Space", KeyNames.Name(KeyNames.Space));
        Assert.Equal("Esc", KeyNames.Name(KeyNames.Escape));
        Assert.Equal("Enter", KeyNames.Name(KeyNames.ReturnKey));
        Assert.Equal("←", KeyNames.Name(Vk.Left));
        Assert.Equal("Page Down", KeyNames.Name(0x22));
        Assert.Equal("Key 0xE8", KeyNames.Name(HotkeyResult.MaskKey));
        var convert = KeyNames.Name(KeyNames.Convert);
        Assert.True(convert is "変換" or "Henkan", convert);
        var hankaku = KeyNames.Name(0xF3);
        Assert.True(hankaku is "半角/全角" or "Hankaku/Zenkaku", hankaku);
    }

    [Fact]
    public void CtrlFirstSwallowsWin()
    {
        var h = new Harness();
        Assert.False(h.Down(Vk.LCtrl).Swallow);
        var win = h.Down(Vk.LWin);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], win.Commands);
        Assert.True(win.Swallow);  // 入力先のアプリに Win を見せない
        Assert.True(h.Down(Vk.LWin).Swallow);  // オートリピート
        var winUp = h.Up(Vk.LWin);
        Assert.True(winUp.Swallow);
        Assert.False(winUp.MaskBeforeRelease);
        Assert.False(h.Up(Vk.LCtrl).Swallow);
        // Ctrl を先に離しても、Win の離しは飲み込む
        h.Down(Vk.LCtrl);
        Assert.True(h.Down(Vk.LWin).Swallow);
        Assert.False(h.Up(Vk.LCtrl).Swallow);
        var up = h.Up(Vk.LWin);
        Assert.True(up.Swallow);
        Assert.Equal([HotkeyCommand.Finish], up.Commands);
    }

    [Fact]
    public void WinFirstIsPassedAndMaskedOnRelease()
    {
        var h = new Harness();
        var win = h.Down(Vk.LWin);
        Assert.Empty(win.Commands);
        Assert.False(win.Swallow);  // Win だけではショートカットかわからない
        var ctrl = h.Down(Vk.LCtrl);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], ctrl.Commands);
        Assert.False(ctrl.Swallow);
        Assert.False(h.Down(Vk.LWin).Swallow);  // 通した Win のオートリピートも通す
        var ctrlUp = h.Up(Vk.LCtrl);
        Assert.False(ctrlUp.Swallow);
        Assert.False(ctrlUp.MaskBeforeRelease);
        var winUp = h.Up(Vk.LWin);
        Assert.False(winUp.Swallow);
        Assert.True(winUp.MaskBeforeRelease);  // 離す前に 0xE8 を挟んでスタートメニューを止める
        // Win を先に離す順でも
        h.Down(Vk.LWin);
        h.Down(Vk.LCtrl);
        var up = h.Up(Vk.LWin);
        Assert.False(up.Swallow);
        Assert.True(up.MaskBeforeRelease);
        Assert.Equal([HotkeyCommand.Finish], h.Up(Vk.LCtrl).Commands);
    }

    [Fact]
    public void RightControlCountsAsControl()
    {
        // リモート デスクトップでは Ctrl が右 Ctrl として届くことがある
        var h = new Harness();
        h.Down(Vk.RCtrl);
        var win = h.Down(Vk.LWin);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], win.Commands);
        Assert.True(win.Swallow);
        h.Up(Vk.LWin);
        Assert.Empty(h.Up(Vk.RCtrl).Commands);
        h.Down(Vk.LCtrl);
        Assert.True(h.Down(Vk.RWin).Swallow);
        h.Up(Vk.RWin);
        Assert.Equal([HotkeyCommand.Finish], h.Up(Vk.LCtrl).Commands);
    }

    [Fact]
    public void ExtraModifierDoesNotMatch()
    {
        var h = new Harness();
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        var win = h.Down(Vk.LWin);  // Ctrl+Alt+Win は Ctrl+Win ではない
        Assert.Empty(win.Commands);
        Assert.False(win.Swallow);
        Assert.False(h.Up(Vk.LWin).MaskBeforeRelease);
        h.Up(Vk.LAlt);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        Assert.Equal(EngineState.Idle, h.State);
        // 左右を決めた修飾キーは、反対側では成り立たない
        h.Engine.Bindings = [(Mode.Dictate, new Shortcut([ModKey.LeftControl, ModKey.Win]))];
        h.Down(Vk.RCtrl);
        Assert.Empty(h.Down(Vk.LWin).Commands);
        h.Up(Vk.LWin);
        h.Up(Vk.RCtrl);
        h.Down(Vk.LCtrl);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.Down(Vk.LWin).Commands);
    }

    [Fact]
    public void RightControlAloneIsAShortcut()
    {
        var h = new Harness();
        h.Engine.Bindings = [(Mode.Dictate, new Shortcut([ModKey.RightControl]))];
        var down = h.Down(Vk.RCtrl);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], down.Commands);
        Assert.True(down.Swallow);
        Assert.True(h.Down(Vk.RCtrl).Swallow);  // オートリピート
        h.Wait(1);
        var up = h.Up(Vk.RCtrl);
        Assert.True(up.Swallow);
        Assert.Equal([HotkeyCommand.Finish], up.Commands);  // 長押し → プッシュトゥトーク
        // 左の Ctrl はショートカットではなく、飲み込まない
        h.State = EngineState.Idle;
        var left = h.Down(Vk.LCtrl);
        Assert.Empty(left.Commands);
        Assert.False(left.Swallow);
        // 左の Ctrl と一緒に押した右の Ctrl は、ほかの修飾キーが混ざるので成り立たない
        var right = h.Down(Vk.RCtrl);
        Assert.Empty(right.Commands);
        Assert.False(right.Swallow);
        Assert.False(h.Up(Vk.RCtrl).Swallow);
        Assert.False(h.Up(Vk.LCtrl).Swallow);
    }

    [Fact]
    public void NonConvertAloneIsAShortcut()
    {
        var h = new Harness();
        h.Engine.Bindings = [(Mode.Dictate, new Shortcut([], KeyNames.NonConvert))];
        var down = h.Down(KeyNames.NonConvert);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], down.Commands);
        Assert.True(down.Swallow);
        Assert.True(h.Down(KeyNames.NonConvert).Swallow);  // オートリピート
        var up = h.Up(KeyNames.NonConvert);
        Assert.True(up.Swallow);
        Assert.Empty(up.Commands);  // 短く押した → ハンズフリー
        Assert.Equal(EngineState.Recording(Mode.Dictate), h.State);
        Assert.True(h.Down(KeyNames.NonConvert).Swallow);
        Assert.Equal([HotkeyCommand.Finish], h.Up(KeyNames.NonConvert).Commands);
        // Shift + 無変換 はショートカットではない
        h.State = EngineState.Idle;
        h.Down(Vk.LShift);
        var shifted = h.Down(KeyNames.NonConvert);
        Assert.Empty(shifted.Commands);
        Assert.False(shifted.Swallow);
        Assert.False(h.Up(KeyNames.NonConvert).Swallow);
        h.Up(Vk.LShift);
    }

    [Fact]
    public void WinShortcutsWithoutCtrlArePassedThrough()
    {
        var h = new Harness();
        foreach (var state in new[] { EngineState.Idle, EngineState.Recording(Mode.Dictate) })
        {
            h.State = state;
            // Win+E
            HotkeyResult[] results = [h.Down(Vk.LWin), h.Down(Vk.E), h.Up(Vk.E), h.Up(Vk.LWin)];
            // Win だけ（スタートメニュー）
            results = [.. results, h.Down(Vk.LWin), h.Up(Vk.LWin)];
            Assert.All(results, r =>
            {
                Assert.Empty(r.Commands);
                Assert.False(r.Swallow);
                Assert.False(r.MaskBeforeRelease);
            });
            Assert.Equal(state, h.State);
        }
    }

    [Fact]
    public void AltIsMaskedWhenItsShortcutKeyWasSwallowed()
    {
        var h = new Harness();
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        h.Down(KeyNames.VKey);
        h.Up(KeyNames.VKey);
        Assert.False(h.Up(Vk.LCtrl).MaskBeforeRelease);
        // 入力先には Alt だけを押して離したように見えるので、メニューバーが開かないように挟む
        var alt = h.Up(Vk.LAlt);
        Assert.True(alt.MaskBeforeRelease);
        Assert.False(alt.Swallow);
        Assert.Equal([HotkeyCommand.PasteLast], alt.Commands);
    }

    [Fact]
    public void UpdateBindingsReadsSettings()
    {
        var settings = new AppSettings { AskShortcuts = [new Shortcut(), Shortcut.CtrlWinSpace] };  // 空のショートカットは読まない
        var engine = new HotkeyEngine();
        engine.UpdateBindings(settings);
        Assert.Equal([(Mode.Dictate, Shortcut.CtrlWin), (Mode.Translate, Shortcut.CtrlWinShift), (Mode.Ask, Shortcut.CtrlWinSpace)], engine.Bindings);
        Assert.Equal([Shortcut.CtrlAltV], engine.PasteBindings);
        Assert.Equal([Shortcut.CtrlAltZ], engine.RevertBindings);
    }

    /// でたらめな順にキーを押して離し、押下を飲み込んだキーは離しも飲み込み、通したキーは離しも通すことを確かめる
    [Fact]
    public void EverySwallowedKeyDownHasItsKeyUpSwallowed()
    {
        int[] keys =
        [
            Vk.LCtrl, Vk.RCtrl, Vk.LShift, Vk.LAlt, Vk.LWin, Vk.RWin,
            KeyNames.Space, KeyNames.VKey, KeyNames.ZKey, KeyNames.Escape, KeyNames.NonConvert, Vk.Left, Vk.E,
        ];
        var h = new Harness();
        h.Engine.Bindings.Add((Mode.Dictate, new Shortcut([ModKey.RightControl])));
        h.Engine.Bindings.Add((Mode.Translate, new Shortcut([], KeyNames.NonConvert)));
        var rng = new Random(20261027);
        // 押しているキー → その押下のどれかを飲み込んだか
        var down = new Dictionary<int, bool>();
        int swallowedUps = 0, maskedUps = 0;
        for (int i = 0; i < 20000; i++)
        {
            if (rng.Next(8) == 0) h.Wait(rng.NextDouble() * 1.5);
            if (h.State == EngineState.Busy && rng.Next(10) == 0) h.State = EngineState.Idle;  // 認識・整形が終わった
            var vk = keys[rng.Next(keys.Length)];
            if (!down.TryGetValue(vk, out var swallowed))
            {
                var r = h.Down(vk);
                Assert.False(r.MaskBeforeRelease);
                down[vk] = r.Swallow;
            }
            else if (rng.Next(3) == 0)
            {
                var r = h.Down(vk);  // オートリピート
                if (swallowed) Assert.True(r.Swallow, $"repeat of {vk:X2} at {i}");
                // 通した Esc も、そのあと録音を始めていればリピートで取り消す（Mac 版と同じ）
                else if (vk != KeyNames.Escape) Assert.False(r.Swallow, $"repeat of {vk:X2} at {i}");
                down[vk] = swallowed || r.Swallow;
            }
            else
            {
                var r = h.Up(vk);
                Assert.True(swallowed == r.Swallow, $"up of {vk:X2} at {i}: down swallowed {swallowed}");
                if (r.MaskBeforeRelease)
                {
                    Assert.False(swallowed);
                    Assert.True(ModKeys.FromVirtualKey(vk)?.AnySide is ModKey.Win or ModKey.Alt);
                    maskedUps++;
                }
                if (r.Swallow) swallowedUps++;
                down.Remove(vk);
            }
        }
        // でたらめな押し方でも、飲み込みと 0xE8 を挟む場面を十分に通っている
        Assert.True(swallowedUps > 100, $"swallowed ups: {swallowedUps}");
        Assert.True(maskedUps > 10, $"masked ups: {maskedUps}");
    }
}
