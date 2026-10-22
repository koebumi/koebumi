import Foundation

/// エージェントの作業フォルダにあるファイル（git が管理しているものと、まだ追加していないもの）。
/// 話したファイル名を、この表記に直すのに使う（AI/FileNameFixer.swift）
struct ProjectFiles: Equatable {
    /// 作業フォルダからのパス
    var paths: [String] = []
    /// 変更中のファイル（音声認識のヒントとして先に渡す）
    var changed: [String] = []

    /// 大きなリポジトリでも読み終わるよう、数を区切る
    static let limit = 5000

    /// git ls-files と git status --porcelain の出力から作る
    init(lsFiles: String, status: String) {
        paths = Array(lsFiles.split(separator: "\n").prefix(Self.limit).map(String.init))
        changed = status.split(separator: "\n").compactMap { line in
            guard line.count > 3 else { return nil }
            // 名前を変えたものは「R  old -> new」
            return line.dropFirst(3).components(separatedBy: " -> ").last
        }
    }

    init(paths: [String] = [], changed: [String] = []) {
        self.paths = paths
        self.changed = changed
    }

    private static let lock = NSLock()
    private static var cache: [String: (date: Date, files: ProjectFiles)] = [:]

    /// この Mac の作業フォルダを git で読む。1 分のあいだ覚えておく。git のリポジトリでなければ空
    static func read(directory: String) -> ProjectFiles {
        if let hit = lock.withLock({ cache[directory] }), Date().timeIntervalSince(hit.date) < 60 { return hit.files }
        guard let git, let list = Subprocess.run(git, gitArguments(directory) + ["ls-files", "--cached", "--others", "--exclude-standard"],
                                                 timeout: 1)
        else { return ProjectFiles() }
        let status = Subprocess.run(git, gitArguments(directory) + ["status", "--porcelain"], timeout: 1) ?? Data()
        let files = ProjectFiles(lsFiles: String(decoding: list, as: UTF8.self), status: String(decoding: status, as: UTF8.self))
        lock.withLock { cache[directory] = (Date(), files) }
        return files
    }

    /// 日本語のパスを「\343\201…」に変えずに書き出す
    private static func gitArguments(_ directory: String) -> [String] { ["-c", "core.quotepath=false", "-C", directory] }

    /// /usr/bin/git は、開発ツールが入っていない Mac ではインストールを促す画面を出すので、入っているときだけ使う
    private static var git: String? {
        let fm = FileManager.default
        if let installed = ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first(where: fm.isExecutableFile(atPath:)) { return installed }
        let developerTools = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        return developerTools.contains(where: fm.isExecutableFile(atPath:)) ? "/usr/bin/git" : nil
    }
}
