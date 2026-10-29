using System.Buffers.Binary;

namespace Koebumi.Core;

/// 16 kHz モノラルの録音データ
public sealed class RecordedAudio(float[] samples, double sampleRate = 16000)
{
    /// -1〜1 のサンプル。書き換えない
    public float[] Samples { get; } = samples;
    public double SampleRate { get; } = sampleRate;

    /// 長さ（秒）
    public double Duration => Samples.Length / SampleRate;

    public float Peak
    {
        get
        {
            float peak = 0;
            foreach (var s in Samples) peak = Math.Max(peak, Math.Abs(s));
            return peak;
        }
    }

    public float Rms
    {
        get
        {
            if (Samples.Length == 0) return 0;
            float sum = 0;
            foreach (var s in Samples) sum += s * s;
            return MathF.Sqrt(sum / Samples.Length);
        }
    }

    /// 声が入っていないとみなす（無音・極端に短い録音）
    public bool IsSilent => Duration < 0.3 || Peak < 0.008f;

    /// ささやき声でも認識しやすいよう、ピークを -1 dBFS 付近まで持ち上げる（最大 +24 dB）。
    public RecordedAudio Normalized()
    {
        var p = Peak;
        if (!(p > 0)) return this;
        var gain = Math.Min(0.89f / p, 16f);
        if (!(gain > 1.05f)) return this;
        var scaled = new float[Samples.Length];
        for (int i = 0; i < scaled.Length; i++) scaled[i] = Samples[i] * gain;
        return new RecordedAudio(scaled, SampleRate);
    }

    /// maxDuration（秒）以下の区間に分ける。単語の途中で切らないよう、区間の後半で声が最も小さい 0.3 秒の中央で区切る。
    public IReadOnlyList<RecordedAudio> Split(double maxDuration)
    {
        int maxCount = (int)(maxDuration * SampleRate);
        int frame = Math.Max((int)(SampleRate / 100), 1);
        const int window = 30;
        if (maxCount < frame * window * 4 || Samples.Length <= maxCount) return [this];
        // 10 ミリ秒ごとの音の大きさ
        var energy = new float[(Samples.Length + frame - 1) / frame];
        for (int f = 0; f < energy.Length; f++)
        {
            float sum = 0;
            int end = Math.Min(f * frame + frame, Samples.Length);
            for (int i = f * frame; i < end; i++) sum += Samples[i] * Samples[i];
            energy[f] = sum;
        }
        float WindowEnergy(int from)
        {
            float sum = 0;
            for (int i = from; i < from + window; i++) sum += energy[i];
            return sum;
        }
        var parts = new List<RecordedAudio>();
        int start = 0;
        while (Samples.Length - start > maxCount)
        {
            int first = (start + maxCount / 2) / frame;
            int last = (start + maxCount) / frame - window;
            int quietest = first;
            float quietestEnergy = WindowEnergy(first);
            for (int c = first + 1; c <= last; c++)
            {
                var e = WindowEnergy(c);
                if (e < quietestEnergy) { quietest = c; quietestEnergy = e; }
            }
            int cut = (quietest + window / 2) * frame;
            parts.Add(new RecordedAudio(Samples[start..cut], SampleRate));
            start = cut;
        }
        parts.Add(new RecordedAudio(Samples[start..], SampleRate));
        return parts;
    }
}

/// 16-bit PCM WAV のエンコード・デコード（履歴の音声保存とクラウド認識のアップロード用）
public static class WAV
{
    public static byte[] Encode(RecordedAudio audio)
    {
        uint sampleRate = (uint)audio.SampleRate;
        uint dataSize = (uint)(audio.Samples.Length * 2);
        var data = new byte[44 + (int)dataSize];
        var span = data.AsSpan();
        "RIFF"u8.CopyTo(span);
        BinaryPrimitives.WriteUInt32LittleEndian(span[4..], 36 + dataSize);
        "WAVE"u8.CopyTo(span[8..]);
        "fmt "u8.CopyTo(span[12..]);
        BinaryPrimitives.WriteUInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteUInt16LittleEndian(span[20..], 1);  // PCM
        BinaryPrimitives.WriteUInt16LittleEndian(span[22..], 1);  // mono
        BinaryPrimitives.WriteUInt32LittleEndian(span[24..], sampleRate);
        BinaryPrimitives.WriteUInt32LittleEndian(span[28..], sampleRate * 2);
        BinaryPrimitives.WriteUInt16LittleEndian(span[32..], 2);
        BinaryPrimitives.WriteUInt16LittleEndian(span[34..], 16);
        "data"u8.CopyTo(span[36..]);
        BinaryPrimitives.WriteUInt32LittleEndian(span[40..], dataSize);
        int offset = 44;
        foreach (var s in audio.Samples)
        {
            var clamped = Math.Max(-1f, Math.Min(1f, s));
            BinaryPrimitives.WriteInt16LittleEndian(span[offset..], (short)(clamped * short.MaxValue));
            offset += 2;
        }
        return data;
    }

    public static RecordedAudio? Decode(ReadOnlySpan<byte> data)
    {
        if (data.Length < 44 || !data[..4].SequenceEqual("RIFF"u8)) return null;
        long offset = 12;
        double sampleRate = 16000;
        int channels = 1;
        while (offset + 8 <= data.Length)
        {
            var id = data.Slice((int)offset, 4);
            long size = BinaryPrimitives.ReadUInt32LittleEndian(data[((int)offset + 4)..]);
            long body = offset + 8;
            if (id.SequenceEqual("fmt "u8))
            {
                if (body + 8 > data.Length) return null;
                channels = BinaryPrimitives.ReadUInt16LittleEndian(data[((int)body + 2)..]);
                sampleRate = BinaryPrimitives.ReadUInt32LittleEndian(data[((int)body + 4)..]);
            }
            else if (id.SequenceEqual("data"u8))
            {
                if (channels < 1) return null;
                long end = Math.Min(body + size, data.Length);
                long count = Math.Max((end - body) / (2L * channels), 0);
                var samples = new float[count];
                long i = body;
                for (long k = 0; k < count; k++, i += 2L * channels)
                    samples[k] = (float)BinaryPrimitives.ReadInt16LittleEndian(data[(int)i..]) / short.MaxValue;
                return new RecordedAudio(samples, sampleRate);
            }
            offset = body + size + (size % 2);
        }
        return null;
    }
}
