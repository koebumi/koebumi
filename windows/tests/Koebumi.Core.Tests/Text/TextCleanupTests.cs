using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class NormalizerTests
{
    [Fact]
    public void RemovesRecognizerSpacesInJapanese()
    {
        Assert.Equal("明日は9時集合ですけど、違う9時半に集合してください。", TextNormalizer.Normalize("明日は 9時集合ですけど、違う 9時半に集合してください。"));
        Assert.Equal("今何時？", TextNormalizer.Normalize("今何時 ？"));
        Assert.Equal("使用する図は概念図の方がいいでしょうか？", TextNormalizer.Normalize("使用する図は概念図の方がいいでしょうか ？"));
        Assert.Equal("会議は3時からです。よろしく", TextNormalizer.Normalize("会議は 3 時からです。 よろしく"));
    }

    [Fact]
    public void KeepsSpacesAroundLatinWords()
    {
        Assert.Equal("src の main.swift を開いて", TextNormalizer.Normalize("src の main.swift を開いて"));
        Assert.Equal("We ship today.", TextNormalizer.Normalize("We ship  today ."));
        Assert.Equal("안녕하세요 반갑습니다", TextNormalizer.Normalize("안녕하세요 반갑습니다"));  // 韓国語は空白で区切る
    }

    [Fact]
    public void FixesWidthAndPunctuation()
    {
        Assert.Equal("ABC123の件です、よろしく。", TextNormalizer.Normalize("ＡＢＣ１２３の件です、よろしく."));
        Assert.Equal("本当？すごい！", TextNormalizer.Normalize("本当?すごい!"));
        Assert.Equal("了解。明日ね。", TextNormalizer.Normalize("了解、、。明日ね。。"));
        Assert.Equal("Version 2.5 is out.", TextNormalizer.Normalize("Version 2.5 is out."));
        Assert.Equal("你好，世界", TextNormalizer.Normalize("你好,世界"));  // 中国語は「，」
        Assert.Equal("了解、3時に行きます", TextNormalizer.Normalize("了解,3時に行きます"));
    }

    [Fact]
    public void FixesFullwidthNumberPunctuation()
    {
        Assert.Equal("約3.5ギガで、1,000円です。", TextNormalizer.Normalize("約３．５ギガで、１，０００円です。"));
        Assert.Equal("10:30に集合", TextNormalizer.Normalize("１０：３０に集合"));
        Assert.Equal("はい，そうです．", TextNormalizer.Normalize("はい，そうです．"));  // 数字の間でなければ変えない
    }

    [Fact]
    public void KeepsLineStructure()
    {
        Assert.Equal("やること:\n1. 資料作成\n2. 返信\n\n以上", TextNormalizer.Normalize("やること:\n1. 資料作成 \n2. 返信\n\n\n\n以上"));
        Assert.Equal("- item\n  - nested", TextNormalizer.Normalize("- item\n  - nested"));
    }
}

public class JapaneseNumbersTests
{
    static string Arabize(string text) => JapaneseNumbers.Arabize(text);

    [Fact]
    public void ConvertsNumbersWithUnits()
    {
        // この Mac のモデル（Qwen3-ASR）で実際に書き起こされた文
        Assert.Equal("明日のミーティングは3時からで、あいや4時からです。", Arabize("明日のミーティングは三時からで、あいや四時からです。"));
        Assert.Equal("明日から3連休です。1日目は海に行って、2日目は山に行って、3日目は空の旅をします。",
            Arabize("明日から三連休です。一日目は海に行って、二日目は山に行って、三日目は空の旅をします。"));
        Assert.Equal("話すことが2つあります。1つ目はメールについて。", Arabize("話すことが二つあります。一つ目はメールについて。"));
        Assert.Equal("3000万。", Arabize("三千万。"));
        Assert.Equal("3000回。", Arabize("三千回。"));
        Assert.Equal("明日から3日間いや4日間アメリカに行きます。", Arabize("明日から三日間いや四日間アメリカに行きます。"));
        Assert.Equal("2泊3日で、1人あたり12万5000円です。", Arabize("二泊三日で、一人あたり十二万五千円です。"));
        Assert.Equal("2026年10月22日の午後1時15分", Arabize("二〇二六年十月二十二日の午後一時十五分"));
        Assert.Equal("1億2000万人", Arabize("一億二千万人"));
        Assert.Equal("3時半に駅の3番線、10分後に出発", Arabize("三時半に駅の三番線、十分後に出発"));
        Assert.Equal("1時から2時間、30人ぐらい", Arabize("一時から二時間、三十人ぐらい"));
        Assert.Equal("500円玉を3枚", Arabize("五百円玉を三枚"));
        Assert.Equal("3月中旬に25パーセント", Arabize("三月中旬に二十五パーセント"));
        Assert.Equal("1.5倍で、全体の3分の1", Arabize("一点五倍で、全体の三分の一"));
        Assert.Equal("第3回の会議", Arabize("第三回の会議"));
    }

    [Fact]
    public void KeepsWordsWithNumerals()
    {
        string[] texts =
        [
            "一緒に行こう", "一番好きな色", "もう一度言って", "一度も行ったことがない", "一時的に止める", "一時はどうなるかと思った",
            "それで十分です", "十分に気をつけて", "三日月がきれい", "三日坊主", "二日酔い", "六本木に行く", "一本化する",
            "統一する", "唯一の方法", "同一人物", "数十人が来た", "何百回も言った", "一人で行く", "一人暮らし", "一人一人に聞く",
            "二度と行かない", "人一倍頑張る", "十人十色", "百人一首", "三位一体", "一回り大きい", "関東一円", "ご一行様",
            "二三日休む", "七五三のお祝い", "〇〇さん", "万が一", "一部の人", "四十七士", "八百屋", "九十九里浜", "一年中", "四日市", "千代田区",
        ];
        foreach (var text in texts)
        {
            Assert.Equal(text, Arabize(text));
        }
    }

    [Fact]
    public void RunsOnlyOnJapanese()
    {
        Assert.Equal("明日の会議は3時からです。", TextNormalizer.Normalize("明日の会議は三時からです。"));
        // かなのない文は、数と単位だけのときに直す。中国語は変えない
        Assert.Equal("3000万。", TextNormalizer.Normalize("三千万。"));
        Assert.Equal("12月20日", TextNormalizer.Normalize("十二月二十日"));
        Assert.Equal("我有三本书", TextNormalizer.Normalize("我有三本书"));
        Assert.Equal("快一点。", TextNormalizer.Normalize("快一点。"));
    }
}

public class ListTidierTests
{
    [Fact]
    public void DropsSpokenEndingOnLastItem()
    {
        Assert.Equal("やることは2つあります。\n1. 資料作成\n2. 返信", ListTidier.Tidy("やることは2つあります。\n1. 資料作成\n2. 返信です。"));
        Assert.Equal("今日やることは3つあります。\n1. 請求書の確認\n2. メールの返信\n3. 来週の準備",
            ListTidier.Tidy("今日やることは3つあります。\n1. 請求書の確認\n2. メールの返信\n3. 来週の準備です。"));
        Assert.Equal("- 牛乳\n- 卵\n- パン", ListTidier.Tidy("- 牛乳\n- 卵\n- パン。"));
    }

    [Fact]
    public void KeepsSentenceItems()
    {
        // 項目がどれも文なら句点は残す
        var steps = "やり方は次のとおりです。\n1. 電源を切ってください。\n2. 5分待ってください。";
        Assert.Equal(steps, ListTidier.Tidy(steps));
        Assert.Equal("明日は晴れです。", ListTidier.Tidy("明日は晴れです。"));
        // 最後の項目の後に続けた文の句点は外さない
        Assert.Equal("1. 資料作成\n2. 返信です。以上です。", ListTidier.Tidy("1. 資料作成\n2. 返信です。以上です。"));
    }
}

// csvKeepsHeardAs（DictionaryStore.parseCSVRows）と dictionaryEntryAliases（DictionaryEntry）は辞書の部分なので、ここには移さない
public class VocabularyTests
{
    readonly Dictionary<string, string> aliases = new()
    {
        ["クロードコード"] = "Claude Code", ["スピーク"] = "Speak", ["cube cuddle"] = "kubectl", ["棚香"] = "田中",
    };

    [Fact]
    public void ReplacesHeardForms()
    {
        Assert.Equal("来週Claude Codeのデモ", VocabularyReplacer.Apply("来週クロードコードのデモ", aliases));
        Assert.Equal("run kubectl get pods", VocabularyReplacer.Apply("run Cube Cuddle get pods", aliases));
        Assert.Equal("田中さんと会います", VocabularyReplacer.Apply("棚香さんと会います", aliases));
    }

    [Fact]
    public void RespectsWordBoundaries()
    {
        Assert.Equal("スピーカーを起動、Speakを起動", VocabularyReplacer.Apply("スピーカーを起動、スピークを起動", aliases));
        Assert.Equal("cube cuddles", VocabularyReplacer.Apply("cube cuddles", aliases));
    }
}

public class SpokenCommandTests
{
    [Fact]
    public void ConvertsStandaloneCommands()
    {
        Assert.Equal("お疲れ様です。\n明日の件です。", SpokenCommands.Apply("お疲れ様です。改行。明日の件です。"));
        Assert.Equal("お疲れ様です\n\n明日の件です", SpokenCommands.Apply("お疲れ様です、段落、明日の件です"));
        Assert.Equal("Thanks.\nBob", SpokenCommands.Apply("Thanks. New line. Bob"));
        Assert.Equal("よろしくお願いします。\n\n田中です。", SpokenCommands.Apply("よろしくお願いします。新しい段落田中です。"));
        Assert.Equal("Hey Tom,\n\nThanks", SpokenCommands.Apply("Hey Tom, new paragraph. Thanks"));
    }

    [Fact]
    public void LeavesWordsInsideSentences()
    {
        Assert.Equal("改行コードはLFにしてください", SpokenCommands.Apply("改行コードはLFにしてください"));
        Assert.Equal("この段落は長いです", SpokenCommands.Apply("この段落は長いです"));
        Assert.Equal("Add a new line here", SpokenCommands.Apply("Add a new line here"));
        Assert.Equal("表の最後に。新しい行を追加して", SpokenCommands.Apply("表の最後に。新しい行を追加して"));
    }
}

public class BasicCleanerTests
{
    [Fact]
    public void RemovesJapaneseFillers()
    {
        Assert.Equal("明日は晴れです", BasicCleaner.Clean("えーと、明日はあの、晴れです"));
        Assert.Equal("明日は9時集合です。", BasicCleaner.Clean("で、明日は 9時集合です。"));
        Assert.Equal("DCワンは概念図を使用しました。そうですね。", BasicCleaner.Clean("DCワンは概念図を使用しました。そうですね。あー。"));
        Assert.Equal("あの人はまあまあです", BasicCleaner.Clean("あの人はまあまあです"));
    }

    [Fact]
    public void FillerOnlySpeechBecomesEmpty()
    {
        Assert.Equal("", BasicCleaner.Clean("えーと、あのー"));
        Assert.Equal("", BasicCleaner.Clean("うーん、えっと、まあ、"));
        Assert.Equal("明日は晴れです。", BasicCleaner.RemoveFillers("えーと、明日は晴れです。"));
        Assert.Equal("まあ、いいか。", BasicCleaner.RemoveFillers("まあ、いいか。"));  // 意味のある語は AI の判断に任せる
        Assert.Equal("やること:\n1. 資料\n2. 返信", BasicCleaner.RemoveFillers("やること:\n1. 資料\nUm, 2. 返信"));  // 行をつなげない
        Assert.Equal("です。\n次の件", BasicCleaner.RemoveFillers("です。えーと\n次の件"));
        Assert.Equal("今日は疲れたなって感じ。", BasicCleaner.RemoveFillers("なんか、今日は疲れたなって感じ。"));
        Assert.Equal("明日は9時半に集合してください。", BasicCleaner.RemoveFillers("で、明日は9時半に集合してください。"));
        Assert.Equal("あの人はなんか、元気だね", BasicCleaner.RemoveFillers("あの人はなんか、元気だね"));  // 文頭だけ
    }

    [Fact]
    public void RemovesEnglishFillersOnly()
    {
        Assert.Equal("So we ship today", BasicCleaner.Clean("um so uh we ship today"));
        Assert.Equal("I think we should ship it", BasicCleaner.Clean("I think, uh, we should, um, ship it"));
        Assert.Equal("Do you know the answer?", BasicCleaner.Clean("Do you know the the answer?"));
        Assert.Equal("Use a 5 mm screw", BasicCleaner.Clean("Use a 5 mm screw"));
    }
}
