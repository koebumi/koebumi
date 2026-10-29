using Koebumi.Core;

namespace Koebumi.Cli;

/// API キーの置き場所。アプリと同じ資格情報マネージャー（Koebumi/<account>）を先に見て、なければ環境変数を使う。
/// コマンドからは保存しない（Set は使えない）。キーの値は、どこにも出さない
sealed class EnvFallbackSecretStore(ISecretStore inner) : ISecretStore
{
    /// 資格情報の名前 → 環境変数。ローカルのサーバー（Ollama・LM Studio・カスタム）にはキーが要らない
    static readonly Dictionary<string, string> Variables = new()
    {
        ["openai"] = "OPENAI_API_KEY",
        ["groq"] = "GROQ_API_KEY",
        ["anthropic"] = "ANTHROPIC_API_KEY",
        ["openrouter"] = "OPENROUTER_API_KEY",
        ["gemini"] = "GEMINI_API_KEY",
    };

    public string? Get(string account) => Find(account).Value;

    public void Set(string value, string account) =>
        throw new NotSupportedException("The koebumi command does not save API keys (use Settings in the app)");

    /// キーの出どころ（--verbose で、どのキーを使ったかの確認に出す。値は含めない）
    public string Source(string account) => Find(account).Source;

    (string? Value, string Source) Find(string account)
    {
        string? stored = null;
        try { stored = inner.Get(account); }
        catch (Exception) { /* 資格情報マネージャーを読めない環境（SSH のセッションなど）では、環境変数に回る */ }
        if (!string.IsNullOrEmpty(stored)) return (stored, "Credential Manager");
        if (Variables.TryGetValue(account, out var name) && Environment.GetEnvironmentVariable(name)?.Trim() is { Length: > 0 } fromEnv)
            return (fromEnv, name);
        return (null, "none");
    }
}
