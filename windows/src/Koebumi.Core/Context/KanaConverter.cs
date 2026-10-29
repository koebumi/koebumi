using System.Text;

namespace Koebumi.Core;

/// かなの変換。Mac 版は macOS の変換（applyingTransform と CFStringTokenizer のローマ字）を使う。
/// Windows 版は読み（IJapaneseReader）がひらがなで届くので、ローマ字（ヘボン式・小文字）への変換もここで持つ
public static class KanaConverter
{
    /// カタカナをひらがなにする（コードポイントを 0x60 ずらす。「ー」はそのまま）
    public static string ToHiragana(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s) sb.Append(c is (>= (char)0x30A1 and <= (char)0x30F6) or (char)0x30FD or (char)0x30FE ? (char)(c - 0x60) : c);
        return sb.ToString();
    }

    /// ひらがなをカタカナにする（コードポイントを 0x60 ずらす）
    public static string ToKatakana(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s) sb.Append(c is (>= (char)0x3041 and <= (char)0x3096) or (char)0x309D or (char)0x309E ? (char)(c + 0x60) : c);
        return sb.ToString();
    }

    /// かな（ひらがな・カタカナ）を小文字のヘボン式ローマ字にする。かな以外の文字（漢字・英数字・記号）はそのまま残す。
    /// 長音の「ー」は直前の母音を重ね、促音の「っ」は次の子音を重ね（「ち」の前は t）、「ん」は n にする。
    /// 長音の書き方は揺れる（おう・おお）ので、比べるときは ScreenNameFixer の緩い比較（ou→o、oo→o など）を使う
    public static string ToRomaji(string s)
    {
        var kana = ToHiragana(s.Normalize(NormalizationForm.FormKC));
        var sb = new StringBuilder(kana.Length * 2);
        bool geminate = false;
        for (int i = 0; i < kana.Length; i++)
        {
            char c = kana[i];
            if (c == 'っ') { geminate = true; continue; }
            if (c == 'ー')
            {
                if (sb.Length > 0 && "aiueo".Contains(sb[^1])) sb.Append(sb[^1]);
                continue;
            }
            if (!Syllables.TryGetValue(c, out var roma))
            {
                geminate = false;
                sb.Append(c);
                continue;
            }
            // きゃ・ふぁ・てぃ のような、小さい「ゃゅょぁぃぅぇぉ」との組み合わせ
            if (i + 1 < kana.Length && Combine(roma, kana[i + 1]) is { } combined)
            {
                roma = combined;
                i++;
            }
            if (geminate && !"aiueo".Contains(roma[0])) sb.Append(roma[0] == 'c' ? 't' : roma[0]);
            geminate = false;
            sb.Append(roma);
        }
        return sb.ToString();
    }

    /// base（ローマ字 1 音）に小さいかな small を付けた音。組み合わせられなければ null
    static string? Combine(string baseRoma, char small)
    {
        switch (small)
        {
            case 'ゃ' or 'ゅ' or 'ょ':
            {
                // 子音 + i の音だけ（しゃ→sha、きゃ→kya）
                if (baseRoma.Length < 2 || baseRoma[^1] != 'i') return null;
                var vowel = small switch { 'ゃ' => 'a', 'ゅ' => 'u', _ => 'o' };
                var stem = baseRoma[..^1];
                return baseRoma is "shi" or "chi" or "ji" ? stem + vowel : stem + "y" + vowel;
            }
            case 'ぁ' or 'ぃ' or 'ぅ' or 'ぇ' or 'ぉ':
            {
                // うぃ→wi、ふぁ→fa、てぃ→ti。母音だけの音には付けない
                var vowel = small switch { 'ぁ' => 'a', 'ぃ' => 'i', 'ぅ' => 'u', 'ぇ' => 'e', _ => 'o' };
                if (baseRoma == "u") return "w" + vowel;
                if (baseRoma.Length < 2 || !"aiueo".Contains(baseRoma[^1])) return null;
                return baseRoma[..^1] + vowel;
            }
            default:
                return null;
        }
    }

    /// ひらがな 1 文字ごとの読み（小さい「ゃゅょぁぃぅぇぉゎ」は、組み合わせられなかったときの単独の読み）
    static readonly Dictionary<char, string> Syllables = Parse(
        "あa いi うu えe おo かka きki くku けke こko さsa しshi すsu せse そso たta ちchi つtsu てte とto " +
        "なna にni ぬnu ねne のno はha ひhi ふfu へhe ほho まma みmi むmu めme もmo やya ゆyu よyo " +
        "らra りri るru れre ろro わwa ゐi ゑe をo んn がga ぎgi ぐgu げge ごgo ざza じji ずzu ぜze ぞzo " +
        "だda ぢji づzu でde どdo ばba びbi ぶbu べbe ぼbo ぱpa ぴpi ぷpu ぺpe ぽpo ゔvu " +
        "ぁa ぃi ぅu ぇe ぉo ゃya ゅyu ょyo ゎwa ゕka ゖke");

    static Dictionary<char, string> Parse(string table) =>
        table.Split(' ').ToDictionary(entry => entry[0], entry => entry[1..]);
}
