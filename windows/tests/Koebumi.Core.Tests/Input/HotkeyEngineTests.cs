using Koebumi.Core;

namespace Koebumi.Core.Tests;

/// 低レベルのキーボードフックに届く仮想キーコード（修飾キーは左右を区別したもの）
file static class Vk
{
    public const int LCtrl = 0xA2, RCtrl = 0xA3, LShift = 0xA0, LAlt = 0xA4, LWin = 0x5B, RWin = 0x5C;
    public const int Left = 0x25, Right = 0x27, E = 0x45, D = 0x44, X = 0x58, F4 = 0x73, Tab = 0x09;
}

/// テスト用の時計を進められる HotkeyEngine
file sealed class Harness
{
    public readonly HotkeyEngine Engine = new();
    public DateTime Clock = DateTime.UnixEpoch.AddSeconds(1000);
    public EngineState State = EngineState.Idle;
    /// 送り直しを求められた修飾キーのすべて（送り直しが起きなかったことを確かめる）
    public readonly List<int> Replayed = [];

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
        Replayed.AddRange(r.Replay);
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

    // ここから、飲み込んだ修飾キーをショートカット以外のキーの前に送り直すテスト（Ctrl+Win+← で仮想デスクトップを切り替えるなど）

    [Fact]
    public void CtrlWinWithArrowReplaysWinBeforeTheKey()
    {
        var h = new Harness();
        var win = h.PressCtrlWin();
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], win.Commands);
        Assert.True(win.Swallow);  // ここまで、入力先のアプリは Win を知らない
        var left = h.Down(Vk.Left);
        Assert.Equal([HotkeyCommand.Abort], left.Commands);  // 録音は今までどおり取り消す
        Assert.Equal([Vk.LWin], left.Replay);  // ← の前に Win の押下を送り直す
        Assert.False(left.Swallow);  // 飲み込むのは Replay を受けたフック（← も一緒に送り直す）。エンジンは Swallow を立てない
        Assert.Equal(EngineState.Idle, h.State);

        // 送り直した Win は、通したキーとして扱う
        var winRepeat = h.Down(Vk.LWin);
        Assert.False(winRepeat.Swallow);
        Assert.Empty(winRepeat.Replay);
        var leftRepeat = h.Down(Vk.Left);  // オートリピート。送り直しは 1 回だけ
        Assert.Empty(leftRepeat.Replay);
        Assert.Empty(leftRepeat.Commands);
        Assert.False(leftRepeat.Swallow);
        Assert.False(h.Up(Vk.Left).Swallow);
        var winUp = h.Up(Vk.LWin);
        Assert.False(winUp.Swallow);
        Assert.False(winUp.MaskBeforeRelease);  // ← を押したあとなので、スタートメニューは開かないはず（実機では未確認）
        var ctrlUp = h.Up(Vk.LCtrl);
        Assert.False(ctrlUp.Swallow);
        Assert.Empty(ctrlUp.Commands);
        Assert.Equal([Vk.LWin], h.Replayed);
        Assert.Equal(EngineState.Idle, h.State);
    }

    [Theory]
    [InlineData(Vk.Left)]
    [InlineData(Vk.Right)]
    [InlineData(Vk.D)]
    [InlineData(Vk.F4)]
    [InlineData(Vk.Tab)]
    public void CtrlWinWithUnrelatedKeyReplaysWin(int key)
    {
        var h = new Harness();
        foreach (var winFirst in new[] { true, false })
        {
            Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.PressCtrlWin().Commands);
            var down = h.Down(key);
            Assert.Equal([HotkeyCommand.Abort], down.Commands);
            Assert.Equal([Vk.LWin], down.Replay);
            Assert.False(down.Swallow);
            Assert.False(h.Up(key).Swallow);
            // 離す順がどちらでも、送り直した Win の離しは通す（飲み込まない・0xE8 を挟まない）
            var first = h.Up(winFirst ? Vk.LWin : Vk.LCtrl);
            var second = h.Up(winFirst ? Vk.LCtrl : Vk.LWin);
            Assert.All(new[] { first, second }, r =>
            {
                Assert.False(r.Swallow);
                Assert.False(r.MaskBeforeRelease);
                Assert.Empty(r.Commands);
                Assert.Empty(r.Replay);
            });
            Assert.Equal(EngineState.Idle, h.State);
        }
        Assert.Equal([Vk.LWin, Vk.LWin], h.Replayed);
    }

    [Fact]
    public void CtrlWinShiftWithArrowReplaysWinAtTheForeignKeyNotAtShift()
    {
        var h = new Harness();
        h.PressCtrlWin();
        // Shift は翻訳のショートカットの続きかもしれないので、まだ送り直さない
        var shift = h.Down(Vk.LShift);
        Assert.Equal([HotkeyCommand.SwitchMode(Mode.Translate)], shift.Commands);
        Assert.Empty(shift.Replay);
        Assert.False(shift.Swallow);
        // ショートカット以外のキーが来て初めて送り直す（Ctrl・Shift は先に届いているので、Win は ← の直前に届く）
        var left = h.Down(Vk.Left);
        Assert.Equal([HotkeyCommand.Abort], left.Commands);
        Assert.Equal([Vk.LWin], left.Replay);
        Assert.Equal(EngineState.Idle, h.State);
        Assert.False(h.Up(Vk.Left).Swallow);
        Assert.False(h.Up(Vk.LShift).Swallow);
        Assert.False(h.Up(Vk.LWin).Swallow);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);

        // Shift を先に押してから Win で Ctrl+Win+Shift を完成させた場合
        var win = h.Down(Vk.LCtrl);
        Assert.Empty(win.Commands);
        h.Down(Vk.LShift);
        win = h.Down(Vk.LWin);
        Assert.Equal([HotkeyCommand.Begin(Mode.Translate)], win.Commands);
        Assert.True(win.Swallow);
        var right = h.Down(Vk.Right);
        Assert.Equal([HotkeyCommand.Abort], right.Commands);
        Assert.Equal([Vk.LWin], right.Replay);
        h.Up(Vk.Right);
        h.Up(Vk.LWin);
        h.Up(Vk.LShift);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);

        // Shift を離してから ← を押しても同じ
        h.PressCtrlWin();
        h.Down(Vk.LShift);
        h.Up(Vk.LShift);
        Assert.Equal([Vk.LWin], h.Down(Vk.Left).Replay);
        Assert.Equal([Vk.LWin, Vk.LWin, Vk.LWin], h.Replayed);
    }

    [Fact]
    public void ModifierKeysAloneNeverReplay()
    {
        var h = new Harness();
        h.PressCtrlWin();
        Assert.Empty(h.Down(Vk.LShift).Replay);
        Assert.Empty(h.Down(Vk.LAlt).Replay);  // Ctrl+Win+Shift+Alt はショートカットではないが、キーが来るまでは何も送らない
        h.Up(Vk.LAlt);
        h.Up(Vk.LShift);
        h.Wait(0.2);
        Assert.True(h.Up(Vk.LWin).Swallow);  // キーを押さなかったので、Win は最後まで入力先に見せない
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        Assert.Empty(h.Replayed);
        Assert.Equal(EngineState.Recording(Mode.Translate), h.State);  // 短い押下 → ハンズフリー（Shift を足したので翻訳）
    }

    [Fact]
    public void CtrlAltWithUnrelatedKeyHasNothingToReplay()
    {
        // Ctrl も Alt も飲み込まずに通しているので、X はそのまま Ctrl+Alt+X として届く
        var h = new Harness();
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        var x = h.Down(Vk.X);
        Assert.Empty(x.Commands);
        Assert.False(x.Swallow);
        Assert.Empty(x.Replay);
        Assert.False(h.Up(Vk.X).Swallow);
        Assert.False(h.Up(Vk.LAlt).MaskBeforeRelease);  // 何も飲み込んでいないので 0xE8 は挟まない
        Assert.Empty(h.Up(Vk.LCtrl).Commands);

        // Ctrl+Alt+V を飲み込んだあとに別のキーが来ても、Ctrl・Alt は送り直さない（先に通してある）
        h.Down(Vk.LCtrl);
        h.Down(Vk.LAlt);
        Assert.True(h.Down(KeyNames.VKey).Swallow);
        var x2 = h.Down(Vk.X);
        Assert.False(x2.Swallow);
        Assert.Empty(x2.Replay);
        h.Up(Vk.X);
        h.Up(KeyNames.VKey);
        h.Up(Vk.LAlt);
        h.Up(Vk.LCtrl);
        Assert.Empty(h.Replayed);
    }

    [Fact]
    public void RightControlAloneIsReplayedWhenCombinedWithAKey()
    {
        // 右 Ctrl だけのショートカットでは、右 Ctrl+C の C が来たときに Ctrl の押下を送り直す
        var h = new Harness();
        h.Engine.Bindings = [(Mode.Dictate, new Shortcut([ModKey.RightControl]))];
        var down = h.Down(Vk.RCtrl);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], down.Commands);
        Assert.True(down.Swallow);
        var c = h.Down(KeyNames.CKey);
        Assert.Equal([HotkeyCommand.Abort], c.Commands);
        Assert.Equal([Vk.RCtrl], c.Replay);
        Assert.False(c.Swallow);
        Assert.False(h.Up(KeyNames.CKey).Swallow);
        var up = h.Up(Vk.RCtrl);
        Assert.False(up.Swallow);
        Assert.False(up.MaskBeforeRelease);
        Assert.Empty(up.Commands);

        // 右 Ctrl を離したあとに押したキーには、送り直すものがない
        h.State = EngineState.Idle;
        h.Down(Vk.RCtrl);
        Assert.True(h.Up(Vk.RCtrl).Swallow);
        var c2 = h.Down(KeyNames.CKey);
        Assert.Empty(c2.Replay);
        Assert.False(c2.Swallow);
        Assert.Equal([Vk.RCtrl], h.Replayed);
    }

    [Fact]
    public void ReplayIsIndependentOfTheRecordingState()
    {
        // 処理中: ショートカットは受け付けないが、Win は飲み込んでいるので送り直す
        var busy = new Harness { State = EngineState.Busy };
        Assert.True(busy.PressCtrlWin().Swallow);
        var left = busy.Down(Vk.Left);
        Assert.Empty(left.Commands);
        Assert.Equal([Vk.LWin], left.Replay);
        Assert.Equal(EngineState.Busy, busy.State);

        // ハンズフリーで録音中にもう一度押している途中: 録音は止めず、Win だけ送り直す
        var h = new Harness();
        h.PressCtrlWin();
        h.ReleaseCtrlWin();
        h.Wait(3);
        Assert.True(h.PressCtrlWin().Swallow);
        var d = h.Down(Vk.D);
        Assert.Empty(d.Commands);
        Assert.Equal([Vk.LWin], d.Replay);
        h.Up(Vk.D);
        h.Up(Vk.LWin);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        Assert.Equal(EngineState.Recording(Mode.Dictate), h.State);
    }

    [Fact]
    public void SeveralSwallowedModifiersAreReplayedInPressOrder()
    {
        var h = new Harness();
        h.Down(Vk.LCtrl);
        Assert.True(h.Down(Vk.LWin).Swallow);
        Assert.True(h.Down(Vk.RWin).Swallow);
        Assert.Equal([Vk.LWin, Vk.RWin], h.Down(Vk.Left).Replay);

        var reversed = new Harness();
        reversed.Down(Vk.LCtrl);
        reversed.Down(Vk.RWin);
        reversed.Down(Vk.LWin);
        Assert.Equal([Vk.RWin, Vk.LWin], reversed.Down(Vk.Left).Replay);
        // 送り直した 2 つとも、離しは通す
        Assert.False(reversed.Up(Vk.LWin).Swallow);
        Assert.False(reversed.Up(Vk.RWin).Swallow);
    }

    [Fact]
    public void PlainCtrlWinNeverReplays()
    {
        var h = new Harness();
        // 短く押してハンズフリー、もう一度押して確定
        Assert.True(h.PressCtrlWin().Swallow);
        h.Wait(0.1);
        Assert.True(h.Up(Vk.LWin).Swallow);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        h.Wait(3);
        h.PressCtrlWin();
        h.Up(Vk.LWin);
        Assert.Equal([HotkeyCommand.Finish], h.Up(Vk.LCtrl).Commands);
        // 長押し（プッシュトゥトーク）
        h.State = EngineState.Idle;
        h.PressCtrlWin();
        h.Wait(2);
        Assert.Equal([HotkeyCommand.Finish], h.ReleaseCtrlWin().Commands);
        // Shift で翻訳、Space で Ask
        h.State = EngineState.Idle;
        h.PressCtrlWin();
        h.Down(Vk.LShift);
        h.Up(Vk.LShift);
        Assert.True(h.Down(KeyNames.Space).Swallow);
        h.Up(KeyNames.Space);
        h.ReleaseCtrlWin();
        // 録音中の Esc
        Assert.True(h.Down(KeyNames.Escape).Swallow);
        h.Up(KeyNames.Escape);
        // 貼り付けと取り消し（Ctrl+Alt+V・Z）
        h.State = EngineState.Idle;
        foreach (var key in new[] { KeyNames.VKey, KeyNames.ZKey })
        {
            h.Down(Vk.LCtrl);
            h.Down(Vk.LAlt);
            Assert.True(h.Down(key).Swallow);
            h.Up(key);
            h.Up(Vk.LAlt);
            h.Up(Vk.LCtrl);
        }
        Assert.Empty(h.Replayed);
    }

    [Fact]
    public void WinFirstHasNothingToReplay()
    {
        // Win を先に押したときは、Win の押下をすでに通している。送り直さず、従来どおり離すときに 0xE8 を挟む
        var h = new Harness();
        Assert.False(h.Down(Vk.LWin).Swallow);
        Assert.Equal([HotkeyCommand.Begin(Mode.Dictate)], h.Down(Vk.LCtrl).Commands);
        var left = h.Down(Vk.Left);
        Assert.Equal([HotkeyCommand.Abort], left.Commands);
        Assert.Empty(left.Replay);
        Assert.False(left.Swallow);
        Assert.False(h.Up(Vk.Left).Swallow);
        var winUp = h.Up(Vk.LWin);
        Assert.False(winUp.Swallow);
        Assert.True(winUp.MaskBeforeRelease);
        Assert.Empty(h.Up(Vk.LCtrl).Commands);
        Assert.Empty(h.Replayed);
    }

    [Fact]
    public void ReplayedWinIsMaskedLikeAPassedWinWhenAShortcutMatchesLater()
    {
        // 送り直した Win は、Win を先に押したときと同じ通した Win。そのあとショートカットが成り立てば、離すときに 0xE8 を挟む
        var h = new Harness();
        h.PressCtrlWin();
        Assert.Equal([Vk.LWin], h.Down(Vk.Left).Replay);
        h.Up(Vk.Left);
        var space = h.Down(KeyNames.Space);
        Assert.Equal([HotkeyCommand.Begin(Mode.Ask)], space.Commands);
        Assert.True(space.Swallow);
        Assert.Empty(space.Replay);
        h.Up(KeyNames.Space);
        var winUp = h.Up(Vk.LWin);
        Assert.False(winUp.Swallow);
        Assert.True(winUp.MaskBeforeRelease);
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
        int swallowedUps = 0, maskedUps = 0, replays = 0;

        // 送り直すのは、押下を飲み込んで、まだ押している修飾キーだけ。送り直したあとは入力先が押下を知っているので、離しは通す
        void NoteReplay(HotkeyResult r, int i)
        {
            foreach (var m in r.Replay)
            {
                Assert.True(ModKeys.IsModifierKey(m) && down.TryGetValue(m, out var wasSwallowed) && wasSwallowed, $"replay of {m:X2} at {i}");
                down[m] = false;
                replays++;
            }
            if (r.Replay.Count > 0) Assert.False(r.Swallow, $"swallowed replay at {i}");
        }

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
                NoteReplay(r, i);
            }
            else if (rng.Next(3) == 0)
            {
                var r = h.Down(vk);  // オートリピート
                if (swallowed) Assert.True(r.Swallow, $"repeat of {vk:X2} at {i}");
                // 通した Esc も、そのあと録音を始めていればリピートで取り消す（Mac 版と同じ）
                else if (vk != KeyNames.Escape) Assert.False(r.Swallow, $"repeat of {vk:X2} at {i}");
                down[vk] = swallowed || r.Swallow;
                NoteReplay(r, i);
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
        Assert.True(replays > 10, $"replays: {replays}");
    }
}
