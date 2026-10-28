using System.Windows;
using System.Windows.Media;

namespace Koebumi.App;

/// 声に合わせて伸びる 9 本の線。黙ると点に戻り、処理中は 3 つの点に集まって波打つ。Mac 版の VoiceDots と同じ動き
public sealed class VoiceDots : FrameworkElement
{
    readonly VoiceDotsMotion motion = new();

    public Brush Ink { get; set; } = Brushes.Black;

    public VoiceDots()
    {
        Width = VoiceDotsMotion.Width;
        Height = 40;
        IsHitTestVisible = false;
    }

    /// 1 コマ進める。level は 0〜1、dt は前のコマからの秒数
    public void Advance(double dt, float level, bool processing, bool still)
    {
        motion.Step(dt, level, processing, still);
        InvalidateVisual();
    }

    /// 動かさずに、いまの状態の形にする（画像に書き出すとき、動きを減らす設定のとき）
    public void Settle(float level, bool processing) => Advance(0, level, processing, true);

    protected override void OnRender(DrawingContext dc) => motion.Draw(dc, new Size(ActualWidth, ActualHeight), Ink);
}

/// VoiceDots の動き。描くたびに経過時間だけ進め、バネの速さや点の集まり具合を前のコマから引き継ぐ
sealed class VoiceDotsMotion
{
    public const double Width = 52;
    const int Count = 9;
    const double Spacing = 6.2;
    /// 線の太さ。黙っているときは、この大きさの点になる
    const double BarWidth = 1.8;
    const double MaxHeight = 28;
    /// 処理中の 3 つの点の大きさ・間隔・上下に動く幅
    const double DotSize = 2.3;
    const double DotSpacing = 4.6;
    const double DotLift = 2.3;
    const double WavePeriod = 1.2;

    readonly double[] heights = Enumerable.Repeat(BarWidth, Count).ToArray();
    readonly double[] velocities = new double[Count];
    /// 線ごとの揺れ方。同じ音量でも線ごとに高さを少しずつ変える
    readonly (double F1, double P1, double F2, double P2)[] wobble = Enumerable.Range(0, Count).Select(_ =>
        (Random.Shared.NextDouble() * 5 + 5, Random.Shared.NextDouble() * 6.28, Random.Shared.NextDouble() * 4 + 3, Random.Shared.NextDouble() * 6.28)).ToArray();
    double envelope;
    double time;
    bool still;
    bool? wasProcessing;
    /// 0 で 3 つの点、1 で 9 本の線。バーが出た直後は 3 つの点から広げる
    double spreadFrom, spreadTo, spreadStart;

    double Spread
    {
        get
        {
            var x = Math.Clamp((time - spreadStart) / 0.33, 0, 1);
            var eased = x < 0.5 ? 4 * x * x * x : 1 - Math.Pow(-2 * x + 2, 3) / 2;
            return spreadFrom + (spreadTo - spreadFrom) * eased;
        }
    }

    public void Step(double dt, double level, bool processing, bool still)
    {
        dt = Math.Clamp(dt, 0, 0.05);
        time += dt;
        this.still = still;
        if (processing != wasProcessing)
        {
            spreadFrom = wasProcessing is null ? 0 : Spread;
            spreadTo = processing ? 0 : 1;
            // 処理に入るときは、線が点に戻るのを少し待ってから集める
            spreadStart = still ? time - 1 : time + (processing ? 0.2 : 0.1);
            wasProcessing = processing;
        }

        // 声が大きくなるときはすぐ追い、小さくなるときはゆっくり下げる
        if (still)
        {
            envelope = level;
        }
        else
        {
            var tau = level > envelope ? 0.04 : 0.2;
            envelope += (level - envelope) * (1 - Math.Exp(-dt / tau));
        }
        var loudness = Math.Min(1, envelope * 1.25);
        for (int i = 0; i < Count; i++)
        {
            var c = (i - 4) / 4.0;
            var profile = 0.45 + 0.55 * Math.Exp(-c * c * 1.6); // 真ん中の線ほど高く伸びる
            var (f1, p1, f2, p2) = wobble[i];
            var jitter = 0.5 + 0.5 * Math.Sin(time * f1 + p1) * Math.Cos(time * f2 + p2);
            var target = processing ? BarWidth : BarWidth + (MaxHeight - BarWidth) * loudness * profile * (0.4 + 0.6 * jitter);
            if (still)
            {
                heights[i] = target;
                velocities[i] = 0;
                continue;
            }
            // バネで追いかけ、少しだけ行き過ぎて戻る
            const double k = 420.0;
            var damping = 2 * 0.72 * Math.Sqrt(k);
            var sub = dt / 3;
            for (int step = 0; step < 3; step++)
            {
                velocities[i] += (k * (target - heights[i]) - damping * velocities[i]) * sub;
                heights[i] += velocities[i] * sub;
            }
            if (heights[i] < BarWidth)
            {
                heights[i] = BarWidth;
                velocities[i] = 0;
            }
        }
    }

    public void Draw(DrawingContext dc, Size size, Brush ink)
    {
        double cx = size.Width / 2, cy = size.Height / 2;
        var s = Spread;
        var w = DotSize + (BarWidth - DotSize) * s;
        for (int i = 0; i < Count; i++)
        {
            // 3 本ずつ左・中・右の点に集まる。処理中の点は右から順に上下する
            double group = i / 3 - 1;
            var dotX = cx + group * DotSpacing;
            var dotY = cy - (still ? 0 : DotLift * Math.Sin(time * 2 * Math.PI / WavePeriod + group * 1.15));
            var lineX = cx + (i - 4) * Spacing;
            var x = dotX + (lineX - dotX) * s;
            var y = dotY + (cy - dotY) * s;
            var h = Math.Max(w, w + (heights[i] - BarWidth) * s);
            dc.DrawRoundedRectangle(ink, null, new Rect(x - w / 2, y - h / 2, w, h), w / 2, w / 2);
        }
    }
}
