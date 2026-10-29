using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;
using Interop.UIAutomationClient;
using Koebumi.Core;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// カーソル位置への入力。クリップボードに文を入れて Ctrl+V を送り、少し後に元のクリップボードを戻す。Mac 版の TextInserter に当たる。
/// 貼り付ける文と、戻す元の内容には、クリップボードの履歴（Win+V）とクラウドのクリップボードに残さない 3 つの形式を付ける。
/// UI スレッドで作って、UI スレッドから使う（クリップボードの持ち主になる窓と、戻す待ちの継続が UI スレッドにあるため）
public sealed class TextInserter : IDisposable
{
    static readonly uint ExcludeFromMonitor = RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");
    static readonly uint CanIncludeInHistory = RegisterClipboardFormat("CanIncludeInClipboardHistory");
    static readonly uint CanUploadToCloud = RegisterClipboardFormat("CanUploadToCloudClipboard");

    /// 修飾キー。1 つでも押したままだと、Ctrl+V が Ctrl+Shift+V や Win+Ctrl+V になる
    static readonly int[] Modifiers = [VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN];

    /// クリップボードの 1 つの形式
    internal sealed record Item(uint Format, byte[] Data);

    /// Electron のアプリはクリップボードを非同期に読むので、少し待ってから戻す
    const int RestoreDelayMs = 600;
    const int ModifierWaitMs = 1000;
    /// Enter で未確定の文字を確定させてから、貼り付けるまで待つ時間
    const int CommitDelayMs = 60;
    /// 変換中かを調べるときに、Chromium のフォーカスを取り直してよい時間
    const int CompositionRetryMs = 250;

    readonly HwndSource owner;
    /// 貼り付けの前の、ユーザーのクリップボード。次の貼り付けが戻す前に来たら、最初の内容を使い回す
    List<Item>? saved;
    int generation;
    uint pastedSequence;

    /// Ctrl+V を送る処理（試験で差し替える）。送れたら true
    internal Func<bool> SendPaste { get; set; } = () => KeySender.Chord(VK_CONTROL, KeyNames.VKey);

    public TextInserter()
    {
        // クリップボードの持ち主にする、メッセージ専用の窓。OpenClipboard(NULL) だと SetClipboardData が失敗するため
        owner = new HwndSource(new HwndSourceParameters("koebumi-clipboard") { ParentWindow = HWND_MESSAGE });
    }

    /// text を入力先に貼り付ける。Ctrl+V を送れたら true（管理者として動くアプリが前面だと、送れても捨てられる）。
    /// keepInClipboard が false なら 600 ms 後に元のクリップボードを戻す（その間にクリップボードが変わっていたら戻さない）。
    /// 戻す前に次の貼り付けが来たら、最初に退避した内容を使い回す
    public async Task<bool> PasteAsync(string text, bool keepInClipboard = false)
    {
        // 先に待つ。文を入れてから待つと、その間ずっとクリップボードが書き換わったままになる
        await WaitForModifiersUp();
        var mine = ++generation;
        if (keepInClipboard) saved = null;
        else if (saved == null) saved = Snapshot();

        // 履歴に残したくないのは、貼り付けのために一時的に入れる文。残すと指定されたときは、ふつうにコピーする
        if (!SetText(text, excludeFromHistory: !keepInClipboard))
        {
            // 前の貼り付けの退避が残っているなら、その分の戻しは続ける
            if (saved != null) _ = RestoreLater(mine);
            return false;
        }
        pastedSequence = GetClipboardSequenceNumber();
        bool sent = SendPaste();
        if (!keepInClipboard) _ = RestoreLater(mine);
        return sent;
    }

    /// カーソル位置に text を入力する（Mac 版の TextInserter.insert）。入力できたら true。
    /// 貼り付けを送れなかった（入力を受けるデスクトップがない、クリップボードを開けない）ときは、結果を失わないようふつうのコピーとして
    /// クリップボードに残して false を返す。変換中の文字があれば、先に Enter で確定させる
    public async Task<bool> InsertAsync(string text, bool keepInClipboard = false)
    {
        // Enter も修飾キーが残っていると Ctrl+Enter などになる（Slack では送信になる）ので、先に待つ
        await WaitForModifiersUp();
        // 変換中（未確定の文字がある）に貼り付けると、メモ帳は確定してから、Chrome・Edge は未確定のまま後ろに貼り付ける（フェーズ 0）。
        // docs/windows.md「決めること」4 の案: 未確定の文字があるときだけ Enter で確定させてから貼り付ける。
        // Enter で確定できるかは、実機でまだ確かめていない
        if (await Task.Run(HasActiveComposition))
        {
            KeySender.Tap(KeyNames.ReturnKey);
            await Task.Delay(CommitDelayMs);
        }
        if (await PasteAsync(text, keepInClipboard)) return true;
        CopyToClipboard(text);
        return false;
    }

    /// ふつうのコピー（履歴に残る）。戻す予定の退避は捨てる
    public bool CopyToClipboard(string text)
    {
        generation++;
        saved = null;
        return SetText(text, excludeFromHistory: false);
    }

    /// 入力欄に変換中（未確定）の文字があるか。UI Automation の TextEditPattern.GetActiveComposition で見る。読めなければ false
    public bool HasActiveComposition()
    {
        // フォーカスのあるアプリの応答が遅いと止まるので、MTA のスレッド プールで読み、待つのは短い間だけ
        var read = Task.Run(() =>
        {
            try
            {
                // 画面の文脈を読まない設定だと、Chromium にはここが最初の問い合わせになり、フォーカスが外側の枠を指している
                var focused = UiAutomation.FocusedElement(CompositionRetryMs, out _);
                if (focused?.GetCurrentPattern(UIA_PatternIds.UIA_TextEditPatternId) is not IUIAutomationTextEditPattern pattern) return false;
                var range = pattern.GetActiveComposition();
                return range != null && range.GetText(1).Length > 0;
            }
            catch (Exception)
            {
                return false;
            }
        });
        return read.Wait(CompositionRetryMs + 150) && read.Result;
    }

    public void Dispose()
    {
        // 終了するときに元のクリップボードを失わない
        generation++;
        RestoreIfUnchanged();
        owner.Dispose();
    }

    async Task RestoreLater(int expected)
    {
        await Task.Delay(RestoreDelayMs);
        if (expected != generation) return;
        RestoreIfUnchanged();
    }

    void RestoreIfUnchanged()
    {
        var items = saved;
        saved = null;
        if (items != null && GetClipboardSequenceNumber() == pastedSequence) Restore(items, excludeFromHistory: true);
    }

    /// 押している修飾キーがすべて離れるまで待つ（最大 1 秒）
    static async Task WaitForModifiersUp()
    {
        var clock = System.Diagnostics.Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < ModifierWaitMs && Modifiers.Any(vk => (GetAsyncKeyState(vk) & 0x8000) != 0))
            await Task.Delay(10);
    }

    // MARK: - クリップボード

    IntPtr Owner => owner.Handle;

    bool Open()
    {
        for (int i = 0; i < 20; i++)
        {
            if (OpenClipboard(Owner)) return true;
            Thread.Sleep(15); // ほかのアプリが開いている
        }
        return false;
    }

    /// GDI のハンドルで持つ形式と、ほかの形式から作られる形式は写さない
    static bool Skip(uint f, HashSet<uint> present) =>
        f is CF_BITMAP or CF_METAFILEPICT or CF_PALETTE or CF_ENHMETAFILE or CF_OWNERDISPLAY or CF_DSPBITMAP or CF_DSPMETAFILEPICT or CF_DSPENHMETAFILE
        || (f >= 0x0200 && f <= 0x03FF) // CF_PRIVATEFIRST〜CF_GDIOBJLAST
        || ((f is CF_TEXT or CF_OEMTEXT) && present.Contains(CF_UNICODETEXT))
        || IsExclusionFormat(f);

    static bool IsExclusionFormat(uint f) => f == ExcludeFromMonitor || f == CanIncludeInHistory || f == CanUploadToCloud;

    /// いまのクリップボードの中身。クリップボードを開けなかったときは null（戻せないので、あとで空にしてしまわない）
    internal List<Item>? Snapshot()
    {
        if (!Open()) return null;
        var items = new List<Item>();
        try
        {
            var formats = new List<uint>();
            for (uint f = EnumClipboardFormats(0); f != 0; f = EnumClipboardFormats(f)) formats.Add(f);
            var present = formats.ToHashSet();
            foreach (var f in formats)
            {
                if (Skip(f, present)) continue;
                var handle = GetClipboardData(f);
                if (handle == IntPtr.Zero) continue;
                var size = (int)GlobalSize(handle);
                if (size <= 0) continue;
                var pointer = GlobalLock(handle);
                if (pointer == IntPtr.Zero) continue;
                var data = new byte[size];
                Marshal.Copy(pointer, data, 0, size);
                GlobalUnlock(handle);
                items.Add(new Item(f, data));
            }
        }
        finally { CloseClipboard(); }
        return items;
    }

    static void Put(uint format, byte[] data)
    {
        var handle = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)Math.Max(1, data.Length));
        var pointer = GlobalLock(handle);
        Marshal.Copy(data, 0, pointer, data.Length);
        GlobalUnlock(handle);
        if (SetClipboardData(format, handle) == IntPtr.Zero) GlobalFree(handle);
    }

    static void PutExclusion()
    {
        Put(ExcludeFromMonitor, BitConverter.GetBytes(0));
        Put(CanIncludeInHistory, BitConverter.GetBytes(0));
        Put(CanUploadToCloud, BitConverter.GetBytes(0));
    }

    internal bool SetText(string text, bool excludeFromHistory)
    {
        if (!Open()) return false;
        try
        {
            EmptyClipboard();
            Put(CF_UNICODETEXT, Encoding.Unicode.GetBytes(text + "\0"));
            if (excludeFromHistory) PutExclusion();
            return true;
        }
        finally { CloseClipboard(); }
    }

    internal bool Restore(List<Item> items, bool excludeFromHistory)
    {
        if (!Open()) return false;
        try
        {
            EmptyClipboard();
            foreach (var item in items) Put(item.Format, item.Data);
            if (excludeFromHistory && items.Count > 0) PutExclusion();
            return true;
        }
        finally { CloseClipboard(); }
    }

    internal string? GetText()
    {
        if (!Open()) return null;
        try
        {
            var handle = GetClipboardData(CF_UNICODETEXT);
            if (handle == IntPtr.Zero) return null;
            var pointer = GlobalLock(handle);
            try { return Marshal.PtrToStringUni(pointer); }
            finally { GlobalUnlock(handle); }
        }
        finally { CloseClipboard(); }
    }

    /// 履歴に残さない形式が 3 つとも付いているか
    internal static bool HasExclusionFormats() =>
        IsClipboardFormatAvailable(ExcludeFromMonitor) && IsClipboardFormatAvailable(CanIncludeInHistory) && IsClipboardFormatAvailable(CanUploadToCloud);
}
