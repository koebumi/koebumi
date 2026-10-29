using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Interop;
using WinClipboard = Windows.ApplicationModel.DataTransfer.Clipboard;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// クリップボード経由の貼り付け。Mac 版の TextInserter.paste と同じく、貼り付けたら少し後に元の内容を戻す。
/// 貼り付けに使った文と、戻した元の内容は、クリップボードの履歴（Win+V）とクラウドのクリップボードに残さない。
/// UI スレッド（Dispatcher のあるスレッド）から呼ぶ。
static class ClipboardPaste
{
    static readonly uint ExcludeFromMonitor = RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing");
    static readonly uint CanIncludeInHistory = RegisterClipboardFormat("CanIncludeInClipboardHistory");
    static readonly uint CanUploadToCloud = RegisterClipboardFormat("CanUploadToCloudClipboard");

    public record Item(uint Format, byte[] Data);

    /// クリップボードの持ち主にする、メッセージ専用の窓。OpenClipboard(NULL) だと SetClipboardData が失敗するため
    static HwndSource? owner;
    static IntPtr Owner => (owner ??= new HwndSource(new HwndSourceParameters("koebumi-phase0-clipboard") { ParentWindow = new IntPtr(-3) /* HWND_MESSAGE */ })).Handle;

    static bool Open()
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
        || ((f is CF_TEXT or CF_OEMTEXT) && present.Contains(CF_UNICODETEXT));

    public static List<Item> Snapshot()
    {
        var items = new List<Item>();
        if (!Open()) return items;
        try
        {
            var formats = new List<uint>();
            for (uint f = EnumClipboardFormats(0); f != 0; f = EnumClipboardFormats(f)) formats.Add(f);
            var present = formats.ToHashSet();
            foreach (var f in formats)
            {
                if (Skip(f, present)) continue;
                var h = GetClipboardData(f);
                if (h == IntPtr.Zero) continue;
                var size = (int)GlobalSize(h);
                if (size <= 0) continue;
                var p = GlobalLock(h);
                if (p == IntPtr.Zero) continue;
                var data = new byte[size];
                Marshal.Copy(p, data, 0, size);
                GlobalUnlock(h);
                items.Add(new Item(f, data));
            }
        }
        finally { CloseClipboard(); }
        return items;
    }

    static IntPtr Global(byte[] data)
    {
        var h = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)Math.Max(1, data.Length));
        var p = GlobalLock(h);
        Marshal.Copy(data, 0, p, data.Length);
        GlobalUnlock(h);
        return h;
    }

    static void Put(uint format, byte[] data)
    {
        var h = Global(data);
        if (SetClipboardData(format, h) == IntPtr.Zero) GlobalFree(h);
    }

    static void PutExclusion()
    {
        Put(ExcludeFromMonitor, BitConverter.GetBytes(0));
        Put(CanIncludeInHistory, BitConverter.GetBytes(0));
        Put(CanUploadToCloud, BitConverter.GetBytes(0));
    }

    public static bool SetText(string text, bool excludeFromHistory)
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

    public static bool Restore(List<Item> items, bool excludeFromHistory)
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

    public static string? GetText()
    {
        if (!Open()) return null;
        try
        {
            var h = GetClipboardData(CF_UNICODETEXT);
            if (h == IntPtr.Zero) return null;
            var p = GlobalLock(h);
            try { return Marshal.PtrToStringUni(p); }
            finally { GlobalUnlock(h); }
        }
        finally { CloseClipboard(); }
    }

    public record PasteResult(uint Sent, bool Restored, double SetMs, int SavedFormats, string Note);

    /// text をクリップボードに入れて Ctrl+V を送り、restoreAfterMs 後に元の内容を戻す（その間にほかのアプリがクリップボードを変えたら戻さない）
    public static async Task<PasteResult> Paste(string text, bool excludeFromHistory = true, int restoreAfterMs = 600)
    {
        var sw = Stopwatch.StartNew();
        var saved = Snapshot();
        if (!SetText(text, excludeFromHistory)) return new PasteResult(0, false, sw.Elapsed.TotalMilliseconds, saved.Count, "クリップボードを開けない");
        var seq = GetClipboardSequenceNumber();
        var setMs = sw.Elapsed.TotalMilliseconds;
        // 押したままの修飾キーが混ざると Ctrl+Shift+V などになる。試作では確かめるだけにする
        var held = new[] { VK_LWIN, VK_RWIN, VK_LSHIFT, VK_RSHIFT, VK_LMENU, VK_RMENU }.Where(vk => (GetAsyncKeyState(vk) & 0x8000) != 0).ToList();
        var sent = KeySender.Chord(VK_CONTROL, 0x56 /* V */);
        await Task.Delay(restoreAfterMs);
        bool restored = false;
        if (GetClipboardSequenceNumber() == seq) restored = Restore(saved, excludeFromHistory: true);
        var note = held.Count > 0 ? "押したままのキー: " + string.Join(",", held.Select(HookEvent.KeyName)) : "";
        return new PasteResult(sent, restored, setMs, saved.Count, note);
    }

    // MARK: - クリップボードの履歴（Win+V）

    public record HistoryCheck(bool Enabled, string Status, int Items, int Matches);

    public static async Task<HistoryCheck> History(string needle)
    {
        try
        {
            if (!WinClipboard.IsHistoryEnabled()) return new HistoryCheck(false, "off", 0, 0);
            var r = await WinClipboard.GetHistoryItemsAsync();
            if (r.Status != Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResultStatus.Success)
                return new HistoryCheck(true, r.Status.ToString(), 0, 0);
            int matches = 0;
            foreach (var item in r.Items)
            {
                if (!item.Content.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text)) continue;
                var text = await item.Content.GetTextAsync();
                if (text.Contains(needle)) matches++;
            }
            return new HistoryCheck(true, "ok", r.Items.Count, matches);
        }
        catch (Exception e) { return new HistoryCheck(true, "error: " + e.Message, 0, 0); }
    }

    /// 試験で履歴に入れた項目を消す
    public static async Task<int> DeleteFromHistory(string needle)
    {
        int deleted = 0;
        try
        {
            var r = await WinClipboard.GetHistoryItemsAsync();
            if (r.Status != Windows.ApplicationModel.DataTransfer.ClipboardHistoryItemsResultStatus.Success) return 0;
            foreach (var item in r.Items)
            {
                if (!item.Content.Contains(Windows.ApplicationModel.DataTransfer.StandardDataFormats.Text)) continue;
                var text = await item.Content.GetTextAsync();
                if (text.Contains(needle) && WinClipboard.DeleteItemFromHistory(item)) deleted++;
            }
        }
        catch { }
        return deleted;
    }
}
