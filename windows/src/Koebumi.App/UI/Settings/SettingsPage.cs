using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 設定の画面の 1 ページ。中身は Build で組み立て、設定が変わって見た目が変わるときは Refresh で組み立て直す
internal abstract class SettingsPage
{
    readonly StackPanel body = new() { MaxWidth = 720, Margin = new Thickness(40, 34, 40, 56) };
    readonly List<Action> flushers = [];

    protected SettingsPage(SettingsWindow host)
    {
        Host = host;
        View = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = body,
        };
    }

    protected SettingsWindow Host { get; }
    protected AppServices Services => Host.Services;
    protected AppSettings S => Services.Settings.Current;

    public ScrollViewer View { get; }
    public abstract string Title { get; }
    /// 左の一覧の記号（Segoe Fluent Icons）
    public abstract string Glyph { get; }

    protected abstract void Build();

    /// 設定を書き換える（すぐ保存する）
    protected void Update(Action<AppSettings> change) => Host.Change(change);

    /// ページを組み立て直す。スクロールの位置は保つ
    public void Refresh()
    {
        FlushPending();
        flushers.Clear();
        double offset = View.VerticalOffset;
        body.Children.Clear();
        Build();
        View.UpdateLayout();
        View.ScrollToVerticalOffset(offset);
    }

    /// 入力の途中の文字を、まだ保存していなければ保存する（ページを移るときと、窓が非アクティブになるとき）
    /// イベントの処理が終わってから組み立て直す（押したボタンを、その処理の途中で消さないため）
    protected void RefreshSoon() => Host.Dispatcher.BeginInvoke(new Action(Refresh));

    public void FlushPending()
    {
        foreach (var flush in flushers.ToArray()) flush();
    }

    protected void Track(Action flush) => flushers.Add(flush);

    /// 上の要素から gap だけ空けて置く
    protected void Add(UIElement element, double gap = 22)
    {
        if (body.Children.Count > 0 && element is FrameworkElement fe)
            fe.Margin = new Thickness(fe.Margin.Left, fe.Margin.Top + gap, fe.Margin.Right, fe.Margin.Bottom);
        body.Children.Add(element);
    }

    protected void AddHeader(string? subtitle = null, UIElement? trailing = null) => Add(Header(Title, subtitle, trailing));

    /// 小見出しとカード。カードは小見出しに近づけて置く
    protected void AddSection(string title, string? subtitle, UIElement card, UIElement? trailing = null, UIElement? note = null)
    {
        Add(Section(title, subtitle, trailing), 26);
        Add(card, 10);
        if (note != null) Add(note, 10);
    }

    /// 文字の入力欄。入力して 0.6 秒たつか、フォーカスが外れるか、Enter を押すと保存する
    protected FrameworkElement Field(string value, string placeholder, Action<string> commit, double width = 260)
    {
        var box = new TextBox { Text = value, Width = width, VerticalContentAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(box, placeholder);
        var hint = Label(placeholder, 14, K.TextTertiary, wrap: false);
        hint.IsHitTestVisible = false;
        hint.Margin = new Thickness(11, 0, 8, 0);
        hint.VerticalAlignment = VerticalAlignment.Center;
        hint.Visibility = value.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        var grid = new Grid { Width = width };
        grid.Children.Add(box);
        grid.Children.Add(hint);

        string committed = value.Trim();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(600) };
        void Commit()
        {
            timer.Stop();
            var text = box.Text.Trim();
            if (text == committed) return;
            committed = text;
            commit(text);
        }
        timer.Tick += (_, _) => Commit();
        box.TextChanged += (_, _) =>
        {
            hint.Visibility = box.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            timer.Stop();
            timer.Start();
        };
        box.LostFocus += (_, _) => Commit();
        box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Commit(); };
        Track(Commit);
        return grid;
    }

    /// API キーの入力欄。キーは資格情報マネージャーに保存し、画面には出さない（保存済みかどうかだけを見せる）。
    /// 入力して Enter・「保存」・フォーカスが外れたときに保存する。「削除」で消す
    protected FrameworkElement ApiKeyField(string account)
    {
        var secrets = Services.Secrets;
        bool saved = SafeGet(secrets, account);
        const double width = 200;
        var box = new PasswordBox { Width = width, VerticalContentAlignment = VerticalAlignment.Center };
        System.Windows.Automation.AutomationProperties.SetName(box, T("API キー", "API key"));
        var hint = Label("", 14, K.TextTertiary, wrap: false);
        hint.IsHitTestVisible = false;
        hint.Margin = new Thickness(11, 0, 8, 0);
        hint.VerticalAlignment = VerticalAlignment.Center;
        var field = new Grid { Width = width };
        field.Children.Add(box);
        field.Children.Add(hint);
        var state = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        var error = Label("", 12, K.Danger);
        error.Margin = new Thickness(0, 4, 0, 0);
        error.Visibility = Visibility.Collapsed;

        void Render()
        {
            hint.Text = saved ? "••••••••••••" : "sk-…";
            hint.Visibility = box.Password.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
            state.Children.Clear();
            if (box.Password.Length > 0)
            {
                state.Children.Add(Btn(T("保存", "Save"), Save));
            }
            else if (saved)
            {
                state.Children.Add(Badge("✓ " + T("保存済み", "Saved")));
                var clear = IconBtn("\uE74D", T("キーを削除", "Remove key"), Remove, size: 28);
                clear.Margin = new Thickness(4, 0, 0, 0);
                state.Children.Add(clear);
            }
        }

        void Save()
        {
            var key = box.Password.Trim();
            if (key.Length == 0) return;
            try
            {
                secrets.Set(key, account);
                saved = true;
                box.Clear();
                error.Visibility = Visibility.Collapsed;
            }
            catch (Exception e)
            {
                error.Text = T("保存できませんでした: ", "Could not save: ") + e.Message;
                error.Visibility = Visibility.Visible;
            }
            Render();
        }

        void Remove()
        {
            try
            {
                secrets.Set("", account);
                saved = false;
                error.Visibility = Visibility.Collapsed;
            }
            catch (Exception e)
            {
                error.Text = T("削除できませんでした: ", "Could not remove: ") + e.Message;
                error.Visibility = Visibility.Visible;
            }
            Render();
        }

        box.PasswordChanged += (_, _) => Render();
        box.LostFocus += (_, _) => Save();
        box.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Save(); };
        Track(Save);
        Render();

        var line = new StackPanel { Orientation = Orientation.Horizontal };
        line.Children.Add(field);
        line.Children.Add(state);
        var column = new StackPanel { HorizontalAlignment = HorizontalAlignment.Right };
        column.Children.Add(line);
        column.Children.Add(error);
        return column;
    }

    static bool SafeGet(ISecretStore secrets, string account)
    {
        try { return !string.IsNullOrEmpty(secrets.Get(account)); }
        catch (Exception) { return false; }
    }
}
