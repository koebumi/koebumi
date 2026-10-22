import Foundation

/// SSH 先のマシン
struct RemoteHost: Hashable {
    /// ssh に渡す接続先（-p・-l などの引数を含む）
    var arguments: [String]
    /// SSH 先の作業フォルダ。分からなければ、SSH 先で自分の Claude Code が動いているフォルダを探す
    var directory: String?
}

enum SSH {
    /// 対話で使っている ssh（ssh mercury、ssh -p 2222 me@host、ssh -t host tmux attach）の、接続に要る引数と接続先。
    /// コマンドを実行するもの（herdr が裏で使う ssh など）や、転送だけのもの（-N）は nil
    static func connection(_ arguments: [String]) -> [String]? {
        guard let first = arguments.first, (first as NSString).lastPathComponent == "ssh" else { return nil }
        var kept: [String] = []
        var tty = false
        var i = 1
        while i < arguments.count, arguments[i].hasPrefix("-"), arguments[i] != "-" {
            let option = arguments[i]
            i += 1
            if option == "--" { break }
            var flags = option.dropFirst()
            while let flag = flags.popFirst() {
                if "bceilmopBDEFIJLOPQRSwW".contains(flag) {
                    // 値を取るオプション（-p2222 と続けて書いても、-p 2222 と分けてもよい）
                    let value = flags.isEmpty ? arguments[safe: i] ?? "" : String(flags)
                    if flags.isEmpty { i += 1 }
                    flags = ""
                    // 接続の操作（-O exit）、問い合わせ（-Q cipher）、標準入出力の転送（-W）
                    if "OQW".contains(flag) { return nil }
                    if "FiJlop".contains(flag) { kept += ["-\(flag)", value] }
                } else if "NfGV".contains(flag) {
                    // 転送だけ（-N）、裏で動かす（-f）、設定や版の表示（-G・-V）
                    return nil
                } else if flag == "t" {
                    tty = true
                } else if "46".contains(flag) {
                    kept.append("-\(flag)")
                }
            }
        }
        guard let destination = arguments[safe: i] else { return nil }
        // 「ssh host ls」のようにコマンドを付けたものは対話で使っていない（-t を付けた「ssh -t host tmux attach」は対話）
        guard i + 1 == arguments.count || tty else { return nil }
        return kept + [destination]
    }
}

/// ssh で読んだ SSH 先のファイル（スラッシュコマンドを探すフォルダの中身と、プラグインの一覧）
struct RemoteFiles: CommandFiles, Equatable {
    var home = ""
    /// SSH 先の作業フォルダ（分からなければ nil）
    var directory: String?
    var folders: [String: [String]] = [:]
    var plugins: Data?

    func list(_ path: String) -> [String] { folders[path] ?? [] }
    func read(_ path: String) -> Data? { path == home + "/.claude/plugins/installed_plugins.json" ? plugins : nil }

    private static let lock = NSLock()
    private static var cache: [RemoteHost: (date: Date, files: RemoteFiles)] = [:]

    /// SSH 先のファイルを ssh で読む。1 分のあいだ覚えておき、つなげなかったときは前に読んだものを使う
    static func read(_ host: RemoteHost) -> RemoteFiles? {
        let cached = lock.withLock { cache[host] }
        if let cached, Date().timeIntervalSince(cached.date) < 60 { return cached.files }
        // パスワードを聞かない（BatchMode）。ssh の設定にある転送や RemoteCommand は使わない
        let options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=2", "-o", "ControlMaster=no", "-o", "RemoteCommand=none",
                       "-o", "ClearAllForwardings=yes", "-T"]
        guard let data = Subprocess.run("/usr/bin/ssh", options + host.arguments + ["sh", "-s"],
                                        input: Data(script(directory: host.directory).utf8), timeout: 3),
              let files = parse(data)
        else { return cached?.files }
        lock.withLock { cache[host] = (Date(), files) }
        return files
    }

    /// SSH 先で、スラッシュコマンドを探すフォルダの中身をまとめて書き出す（1 回の接続で済ませる）。
    /// 作業フォルダが分からなければ、自分の Claude Code のプロセスがみな同じフォルダにいるときだけ、そのフォルダを使う（Linux の /proc で読む）
    static func script(directory: String?) -> String {
        let quoted = "'" + (directory ?? "").replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        return #"""
        list() { printf '\001%s\n' "$1"; ls -1pL "$1" 2>/dev/null; }
        d=\#(quoted)
        if [ -z "$d" ]; then
          d=$(for p in $(pgrep -u "$(id -u)" -f '^([^ ]*/)?claude( |$)' 2>/dev/null); do readlink "/proc/$p/cwd"; done | sort -u)
          case "$d" in *'
        '*) d= ;; esac
        fi
        printf '\002%s\n' "$HOME" "$d"
        list "$HOME/.claude/skills"; list "$HOME/.claude/commands"; list "$HOME/.codex/prompts"
        if [ -n "$d" ]; then list "$d/.claude/skills"; list "$d/.claude/commands"; fi
        f="$HOME/.claude/plugins/installed_plugins.json"
        grep -o '"installPath" *: *"[^"]*"' "$f" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/' | while IFS= read -r p; do list "$p/skills"; list "$p/commands"; done
        printf '\003\n'; cat "$f" 2>/dev/null
        exit 0
        """#
    }

    /// script の出力を読む。\u{2} の行はホームと作業フォルダ、\u{1} の行はフォルダのパス（続く行がその中身）、\u{3} の後はプラグインの一覧
    static func parse(_ output: Data) -> RemoteFiles? {
        let text = String(decoding: output, as: UTF8.self)
        // 最後まで書き出せなかったものは使わない
        guard let end = text.range(of: "\u{3}\n") else { return nil }
        var files = RemoteFiles()
        var header: [String] = []
        var folder: String?
        for line in text[..<end.lowerBound].split(separator: "\n") {
            if line.hasPrefix("\u{2}") {
                header.append(String(line.dropFirst()))
            } else if line.hasPrefix("\u{1}") {
                folder = String(line.dropFirst())
            } else if let folder {
                files.folders[folder, default: []].append(String(line))
            }
        }
        guard let home = header.first, !home.isEmpty else { return nil }
        files.home = home
        files.directory = header.dropFirst().first.flatMap { $0.isEmpty ? nil : $0 }
        let json = text[end.upperBound...]
        files.plugins = json.isEmpty ? nil : Data(json.utf8)
        return files
    }
}
