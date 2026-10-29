using Koebumi.Core;

namespace Koebumi.Core.Tests;

// Mac 版の LogicTests.swift の TextTests のうち、この部分（Text/）の処理だけを使うもの。
// ほかのテスト（cleanOutputStripsWrappers など）は別の部分にあるので、partial にして同じクラスに足せるようにする
public partial class TextTests
{
    [Fact]
    public void BasicCleanerRemovesFillers()
    {
        Assert.Equal("明日は晴れです", BasicCleaner.Clean("えーと、明日はあの、晴れです"));
        Assert.Equal("So we ship today", BasicCleaner.Clean("um so uh we ship today"));
    }
}
