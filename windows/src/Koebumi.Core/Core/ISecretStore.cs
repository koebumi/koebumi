namespace Koebumi.Core;

/// API キーの置き場所。アプリは資格情報マネージャー（CredWrite・CredRead）、テストはメモリに置く
public interface ISecretStore
{
    string? Get(string account);
    void Set(string value, string account);
}

public sealed class MemorySecretStore : ISecretStore
{
    readonly Dictionary<string, string> values = [];
    public string? Get(string account) => values.TryGetValue(account, out var v) ? v : null;
    public void Set(string value, string account)
    {
        if (string.IsNullOrEmpty(value)) values.Remove(account);
        else values[account] = value;
    }
}
