using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Koebumi.Core;
using static Koebumi.App.Native;

namespace Koebumi.App;

/// API キーを Windows の資格情報マネージャーに置く。Mac 版の Keychain に当たる。
/// 資格情報の名前は "Koebumi/<account>"、値は UTF-16 のまま、この PC だけに保存する（ローミングしない）
public sealed class CredentialStore : ISecretStore
{
    static string Target(string account) => "Koebumi/" + account;

    /// 保存した値。なければ null
    public string? Get(string account)
    {
        if (!CredRead(Target(account), CRED_TYPE_GENERIC, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<CREDENTIAL>(pointer);
            if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero) return null;
            return Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
        }
        finally { CredFree(pointer); }
    }

    /// 保存する。value が空なら消す。保存できなければ Win32Exception
    public void Set(string value, string account)
    {
        var target = Target(account);
        if (string.IsNullOrEmpty(value))
        {
            if (!CredDelete(target, CRED_TYPE_GENERIC, 0) && Marshal.GetLastWin32Error() != ERROR_NOT_FOUND)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return;
        }
        var bytes = Encoding.Unicode.GetBytes(value);
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new CREDENTIAL
            {
                Type = CRED_TYPE_GENERIC,
                TargetName = target,
                UserName = account,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = CRED_PERSIST_LOCAL_MACHINE,
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            Array.Clear(bytes);
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            Marshal.FreeHGlobal(blob);
        }
    }
}
