import Foundation

/// Claude Code に入れるスキル（~/.claude/skills/koebumi-dictionary/SKILL.md）。
/// エージェントがリポジトリの用語を選び、聞き取られ方を付けて `Koebumi --dictionary add` で辞書に登録できるようにする。
enum DictionarySkill {
    static let name = "koebumi-dictionary"
    /// Koebumi が書いたスキルの目印。目印のない同じ名前のスキル（ユーザーが自分で書いたもの）は上書きも削除もしない
    static let marker = "<!-- Installed by Koebumi. Remove it in Koebumi: Dictionary > Claude Code skill. -->"

    enum Status: Equatable {
        case notInstalled
        case installed
        /// Koebumi が書いたが、中身が今の版と違う（アプリを動かした、またはスキルの文面が変わった）
        case outdated
        /// 同じ名前の、Koebumi が書いたのではないスキルがある
        case foreign
    }

    static func file(home: String = NSHomeDirectory()) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".claude/skills/\(name)/SKILL.md")
    }

    static func status(executable: String, home: String = NSHomeDirectory()) -> Status {
        guard let text = try? String(contentsOf: file(home: home), encoding: .utf8) else { return .notInstalled }
        guard text.contains(marker) else { return .foreign }
        return text == document(executable: executable) ? .installed : .outdated
    }

    static func install(executable: String, home: String = NSHomeDirectory()) throws {
        guard status(executable: executable, home: home) != .foreign else { return }
        let url = file(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(document(executable: executable).utf8).write(to: url, options: [.atomic])
    }

    static func uninstall(home: String = NSHomeDirectory()) throws {
        let url = file(home: home)
        guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains(marker) else { return }
        try FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 入れてあるスキルを今の版に書き直す（アプリの起動時。アプリを動かしてもコマンドのパスが古くならないように）
    static func refreshIfInstalled(executable: String, home: String = NSHomeDirectory()) {
        guard status(executable: executable, home: home) == .outdated else { return }
        try? install(executable: executable, home: home)
    }

    /// パスを 1 つのシェルの語にする。単引用符で囲めば、空白や $ を含むフォルダ名でもコマンドが変わらない
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func document(executable: String) -> String {
        let tool = shellQuoted(executable)
        return """
        ---
        name: \(name)
        description: "Add words to the user's Koebumi voice-input dictionary so dictation spells them correctly. \
        Use when the user asks to put a repository's or project's terms into Koebumi's dictionary (Koebumi の辞書), \
        or says dictation keeps mishearing a word."
        ---
        \(marker)

        # Koebumi dictionary

        Koebumi is the user's voice-input app. Each dictionary entry is a term plus its *heard-as* spellings:

        - The term is given to speech recognition and to the AI cleanup as an exact spelling. Only the newest 60 to 100 terms fit, so every term spends a shared budget.
        - Each heard-as spelling is replaced with the term wherever it appears in a transcript, with no limit on count. This is the part that reliably works: Japanese speech recognition writes English names in katakana (Claude Code → クロードコード).

        Call the tool by its full path, quoted exactly as shown:

        ```
        \(tool) --dictionary list
        ```

        ## Commands

        - `--dictionary list` - current entries, one per line as `TERM=HEARD|HEARD`. `(auto)` marks words Koebumi learned from the user's own corrections. Add `--json` for structured output.
        - `--dictionary add "TERM=HEARD|HEARD" ...` - one quoted argument per term. Adds new terms, and new heard-as spellings to terms already there.
        - `--dictionary remove TERM ...` - removes terms.

        The running app picks up changes immediately.

        ## Adding a project's terms

        1. Run `list` to see what is already registered.
        2. Pick the terms speech recognition gets wrong: product and library names, acronyms, CamelCase identifiers, people's names, the project's own jargon. Keep to the 30 most valuable, and spell each exactly as the user writes it. Koebumi already fixes file names the user speaks to Claude Code or Codex, so a name that is only a file name earns a place only when the user also talks about it elsewhere, such as Slack or email.
        3. Give every term its heard-as spellings: how Japanese speech recognition writes it when the user says it in Japanese. Usually katakana, plus the common variant (`ディクテーションコントローラー|ディクテーションコントローラ`). Each spelling is replaced everywhere, so use only spellings that never occur as ordinary words. `ゴー` for `Go` would rewrite everyday speech.
        4. Show the user a table of term, heard-as and why, and wait for their go-ahead.
        5. Run `add` once with every approved term, then report the result lines. The user can review and edit entries in Koebumi > Dictionary.

        ## Fixing one misheard word

        Ask how the word came out, then `add` the term with that spelling as heard-as. Kanji and hiragana spellings are replaced everywhere too, so use one only when it is not a common word (公園 for 講演 would break ordinary sentences).

        ## If it does not work

        - The command is not found: Koebumi was moved or removed. Ask the user to open Koebumi > Dictionary and install the Claude Code skill again.
        - `could not save`: something blocked writing to Koebumi's data folder, often the agent's sandbox. Ask the user to allow the command to run outside the sandbox.
        """ + "\n"
    }
}
