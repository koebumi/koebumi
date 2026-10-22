import AppKit
import Foundation

/// 開発用: 日本語の表記・敬語・画面の文脈の効果を、実際のモデルで確かめるコマンド。
///   Speak --eval cases.json [--trials 3] [--llm …] [--json]       変更前の設定と比べて採点する
///   Speak --read-context [--delay 3]                               最前面の入力欄と画面の文字列を読んで表示する
///   Speak --detect-agent [--delay 3] [--screen FILE] [--herdr-pane ID]   最前面の端末で動いている Claude Code・Codex を見分ける
///   Speak --context-demo "書き起こし" [--delay 3] [--category chat]   読んだ文脈で整形し、最前面の入力欄に入力する
///   Speak --answer-prompt "はい" [--delay 3]                       最前面の Claude Code が出している許可の確認に答える
@MainActor
enum Eval {
    struct Case: Decodable {
        var id: String
        var transcript: String
        var category: AppCategory = .other
        var preset: StylePreset = .auto
        var language: String = "ja-JP"
        var notation: JapaneseNotation?
        var chatPunctuation: ChatPunctuation = .keep
        var before: String = ""
        var after: String = ""
        var screen: String = ""
        /// すべて含む
        var expect: [String] = []
        /// 各グループのどれか 1 つを含む
        var expectAny: [[String]] = []
        /// どれも含まない
        var forbid: [String] = []
        /// この文字列で終わらない
        var forbidSuffix: [String] = []
        var expectPrefix: String?

        enum CodingKeys: String, CodingKey {
            case id, transcript, category, preset, language, notation, chatPunctuation, before, after, screen, expect, expectAny, forbid, forbidSuffix, expectPrefix
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            transcript = try c.decode(String.self, forKey: .transcript)
            category = try c.decodeIfPresent(AppCategory.self, forKey: .category) ?? .other
            preset = try c.decodeIfPresent(StylePreset.self, forKey: .preset) ?? .auto
            language = try c.decodeIfPresent(String.self, forKey: .language) ?? "ja-JP"
            notation = try c.decodeIfPresent(JapaneseNotation.self, forKey: .notation)
            chatPunctuation = try c.decodeIfPresent(ChatPunctuation.self, forKey: .chatPunctuation) ?? .keep
            before = try c.decodeIfPresent(String.self, forKey: .before) ?? ""
            after = try c.decodeIfPresent(String.self, forKey: .after) ?? ""
            screen = try c.decodeIfPresent(String.self, forKey: .screen) ?? ""
            expect = try c.decodeIfPresent([String].self, forKey: .expect) ?? []
            expectAny = try c.decodeIfPresent([[String]].self, forKey: .expectAny) ?? []
            forbid = try c.decodeIfPresent([String].self, forKey: .forbid) ?? []
            forbidSuffix = try c.decodeIfPresent([String].self, forKey: .forbidSuffix) ?? []
            expectPrefix = try c.decodeIfPresent(String.self, forKey: .expectPrefix)
        }

        func failures(_ output: String) -> [String] {
            var f: [String] = []
            for e in expect where !output.contains(e) { f.append("missing \(e)") }
            for group in expectAny where !group.contains(where: output.contains) { f.append("missing one of \(group.joined(separator: "|"))") }
            for e in forbid where output.contains(e) { f.append("contains \(e)") }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            for e in forbidSuffix where trimmed.hasSuffix(e) { f.append("ends with \(e)") }
            if let p = expectPrefix, !output.hasPrefix(p) { f.append("does not start with \"\(p)\"") }
            return f
        }
    }

    static func run(_ args: [String]) async -> Int32 {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        var settings = SettingsStore.shared.settings
        if let llm = value("--llm").flatMap(LLMProvider.init(rawValue:)) { settings.llmProvider = llm }
        if let model = value("--model") {
            settings.claudeModel = model
            settings.codexModel = model
            settings.compatModels[settings.compatService.rawValue] = model
        }
        let delay = value("--delay").flatMap(Double.init) ?? 0

        if args.contains("--read-context") {
            try? await Task.sleep(for: .seconds(delay))
            if let role = value("--focus-first") { focusFirst(role: role) }
            let t0 = Date()
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let s = await Task.detached { SurroundingTextReader.read(pid: pid, includeScreen: true) }.value
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            let fields: [String: Any] = [
                "app": NSWorkspace.shared.frontmostApplication?.localizedName ?? "?",
                "ms": ms, "before": s?.before ?? "", "after": s?.after ?? "", "screen": s?.screen ?? "", "terms": s?.terms ?? [],
            ]
            printJSON(fields)
            return s == nil ? 1 : 0
        }

        if args.contains("--detect-agent") {
            try? await Task.sleep(for: .seconds(delay))
            guard let app = NSWorkspace.shared.frontmostApplication else { return 1 }
            let pid = app.processIdentifier
            let t0 = Date()
            // --screen FILE: 保存した画面の文字列で試す（画面の文字だけで見分ける）
            if let screen = value("--screen").flatMap({ try? String(contentsOfFile: $0, encoding: .utf8) }) {
                printJSON(["agents": CodingAgent.detect(in: screen).map(\.name), "chars": screen.count,
                           "prompt": CodingAgent.permissionPrompt(in: screen)?.options ?? []])
                return 0
            }
            let title = AppContext.current(overrides: [:]).windowTitle
            // --herdr-pane ID: herdr の区画を指定して、許可の確認を読む（選んでいない区画でも試せる）
            if let pane = value("--herdr-pane") {
                let prompt = await Task.detached { AgentWorkspace.permissionPrompt(pid: pid, windowTitle: title, herdrPane: pane) }.value
                printJSON(["title": title ?? "", "prompt": prompt?.options ?? []])
                return 0
            }
            let target = await Task.detached { AgentWorkspace.locate(pid: pid, windowTitle: title) }.value
            printJSON(["app": app.localizedName ?? "?", "title": title ?? "", "terminal": CodingAgent.isTerminal(app.bundleIdentifier),
                       "agents": target.agents.map(\.name), "directory": target.directory ?? "",
                       "hosts": target.hosts.map { $0.arguments.joined(separator: " ") + ($0.directory.map { ":" + $0 } ?? "") },
                       "commands": target.commands, "prompt": target.prompt?.options ?? [],
                       "ms": Int(Date().timeIntervalSince(t0) * 1000)])
            return 0
        }

        // 最前面の端末の Claude Code が出している許可の確認に、話す代わりに文字で答える（「いいえ、〜」の続きは整形せずに入力する）
        if let spoken = value("--answer-prompt") {
            try? await Task.sleep(for: .seconds(delay))
            guard let app = NSWorkspace.shared.frontmostApplication else { return 1 }
            let pid = app.processIdentifier
            let title = AppContext.current(overrides: [:]).windowTitle
            let target = await Task.detached { AgentWorkspace.locate(pid: pid, windowTitle: title) }.value
            guard let prompt = target.prompt, let answer = AgentInput.answer(spoken, to: prompt) else {
                printJSON(["app": app.localizedName ?? "?", "prompt": target.prompt?.options ?? [], "choice": "(none)"])
                return 1
            }
            await TextInserter.choose(moving: answer.choice - prompt.selected)
            if let rest = answer.rest {
                try? await Task.sleep(for: .milliseconds(300))
                await TextInserter.paste(rest, keepInClipboard: false)
                await TextInserter.pressReturn()
            }
            try? await Task.sleep(for: .milliseconds(800))
            printJSON(["app": app.localizedName ?? "?", "choice": "\(answer.choice + 1). \(prompt.options[answer.choice])",
                       "rest": answer.rest ?? ""])
            return 0
        }

        // 画面の語を音声認識のヒントに渡したときと渡さないときの認識結果を比べる
        if let path = value("--stt-terms-test") {
            let lang = value("--lang") ?? "ja-JP"
            let terms = (value("--terms") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            do {
                let audio = try CLI.loadAudio(URL(fileURLWithPath: path))
                let transcriber = TranscriberFactory.make(settings: settings, language: lang)
                let plain = try await transcriber.transcribe(audio, TranscriptionRequest(languages: [lang], vocabulary: []))
                let hinted = try await transcriber.transcribe(audio, TranscriptionRequest(languages: [lang], vocabulary: terms))
                printJSON(["without_terms": plain, "with_terms": hinted, "terms": terms])
                return 0
            } catch {
                print("ERROR: \(error.localizedDescription)")
                return 1
            }
        }

        if let transcript = value("--context-demo") {
            try? await Task.sleep(for: .seconds(delay))
            if let role = value("--focus-first") { focusFirst(role: role) }
            let category = value("--category").flatMap(AppCategory.init(rawValue:)) ?? .other
            let t0 = Date()
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let surrounding = await Task.detached { SurroundingTextReader.read(pid: pid, includeScreen: true) }.value
            let readMs = Int(Date().timeIntervalSince(t0) * 1000)
            var request = request(transcript: transcript, category: category, preset: settings.style(for: category),
                                  notation: settings.japaneseNotation, surrounding: surrounding, inPrompt: settings.shareSurroundingWithLLM)
            request.chatPunctuation = settings.chatPunctuation
            let t1 = Date()
            do {
                let out = try await Polisher.run(request, engine: engine(settings))
                let pasted = await TextInserter.insert(out.text, keepInClipboard: false)
                try? await Task.sleep(for: .milliseconds(800))
                printJSON(["read_ms": readMs, "polish_ms": Int(Date().timeIntervalSince(t1) * 1000), "inserted": out.text, "pasted": pasted,
                           "before": surrounding?.before ?? "", "after": surrounding?.after ?? "", "screen_chars": surrounding?.screen.count ?? 0])
                return 0
            } catch {
                print("ERROR: \(error.localizedDescription)")
                return 1
            }
        }

        guard let path = value("--eval"), let data = FileManager.default.contents(atPath: path) else {
            print("usage: Speak --eval cases.json [--trials N] [--llm appleOnDevice|claude] | --read-context [--delay S] | --detect-agent [--delay S] [--screen FILE] | --context-demo TEXT [--delay S] [--category chat] | --answer-prompt TEXT [--delay S]")
            return 2
        }
        let cases: [Case]
        do {
            cases = try JSONDecoder().decode([Case].self, from: data)
        } catch {
            print("ERROR: \(error)")
            return 2
        }
        let trials = value("--trials").flatMap(Int.init) ?? 1
        let engine = engine(settings)
        var totals = (before: 0, after: 0, runs: 0)
        var rows: [[String: Any]] = []
        for c in cases {
            for trial in 1...trials {
                // 変更前: 表記ルール・画面の文脈なし。敬語は以前の「フォーマル」の指示
                let oldStyle = c.preset == .auto ? c.category.defaultStyleDescription
                    : c.category.defaultStyleDescription + " Formal and polite register (in Japanese: 丁寧語/敬語)."
                var baseline = request(transcript: c.transcript, category: c.category, preset: .auto, notation: nil, surrounding: nil, inPrompt: false)
                baseline.styleDescription = oldStyle
                baseline.sourceLanguages = [c.language]
                var improved = request(transcript: c.transcript, category: c.category, preset: c.preset,
                                       notation: c.notation ?? JapaneseNotation(),
                                       surrounding: SurroundingText(before: c.before, after: c.after, screen: c.screen), inPrompt: true)
                improved.sourceLanguages = [c.language]
                improved.chatPunctuation = c.chatPunctuation
                improved.allowsRewording = c.preset != .auto
                let tb = Date()
                let b = (try? await Polisher.run(baseline, engine: engine).text) ?? "ERROR"
                let bms = Int(Date().timeIntervalSince(tb) * 1000)
                let t0 = Date()
                let a = (try? await Polisher.run(improved, engine: engine).text) ?? "ERROR"
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                if args.contains("--raw"), let engine {
                    // AI の出力そのもの（OutputGuard と表記の統一の前）
                    var r = improved
                    r.transcript = Polisher.prepare(r.transcript, aliases: [:])
                    let raw = (try? await engine.polish(r)) ?? "ERROR"
                    print("  raw:    \(raw.replacingOccurrences(of: "\n", with: "⏎"))  guard=\(OutputGuard.accepts(source: r.transcript, output: raw))")
                }
                let fb = c.failures(b), fa = c.failures(a)
                totals.runs += 1
                if fb.isEmpty { totals.before += 1 }
                if fa.isEmpty { totals.after += 1 }
                rows.append(["id": c.id, "trial": trial, "before": b, "after": a, "before_ok": fb.isEmpty, "after_ok": fa.isEmpty,
                             "before_fail": fb, "after_fail": fa, "before_ms": bms, "after_ms": ms])
                if !args.contains("--json") {
                    print("[\(c.id) #\(trial)] before \(fb.isEmpty ? "PASS" : "FAIL") | after \(fa.isEmpty ? "PASS" : "FAIL") (\(ms) ms)")
                    print("  before: \(b.replacingOccurrences(of: "\n", with: "⏎"))" + (fb.isEmpty ? "" : "  ← \(fb.joined(separator: ", "))"))
                    print("  after:  \(a.replacingOccurrences(of: "\n", with: "⏎"))" + (fa.isEmpty ? "" : "  ← \(fa.joined(separator: ", "))"))
                }
            }
        }
        if args.contains("--json") {
            printJSON(["engine": engine?.name ?? "basic", "runs": totals.runs, "before_pass": totals.before, "after_pass": totals.after, "rows": rows])
        } else {
            print("\nengine: \(engine?.name ?? "basic")  runs: \(totals.runs)  before: \(totals.before)/\(totals.runs) pass  after: \(totals.after)/\(totals.runs) pass")
        }
        return 0
    }

    /// 検証用: 最前面のウィンドウで最初に見つかった role の要素にフォーカスを移し、カーソルを末尾に置く
    private static func focusFirst(role: String) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return }
        func find(_ el: AXUIElement, _ depth: Int) -> AXUIElement? {
            guard depth < 40 else { return nil }
            var r: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r)
            if r as? String == role { return el }
            var children: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children)
            for c in children as? [AXUIElement] ?? [] { if let hit = find(c, depth + 1) { return hit } }
            return nil
        }
        guard let target = find(window as! AXUIElement, 0) else { return }
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        var length: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXNumberOfCharactersAttribute as CFString, &length)
        var range = CFRange(location: (length as? NSNumber)?.intValue ?? 0, length: 0)
        if let v = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, v)
        }
    }

    private static func engine(_ settings: AppSettings) -> LLMEngine? {
        if settings.llmProvider == .claude, let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] {
            return ClaudeEngine(apiKey: key, model: settings.claudeModel, webSearch: false)
        }
        return LLMFactory.make(settings: settings)
    }

    private static func request(transcript: String, category: AppCategory, preset: StylePreset, notation: JapaneseNotation?,
                                surrounding: SurroundingText?, inPrompt: Bool) -> PolishRequest {
        PolishRequest(transcript: transcript, mode: .dictate, sourceLanguages: ["ja-JP"], targetLanguage: nil,
                      appName: category.title, category: category, styleDescription: preset.styleDescription(for: category),
                      personalStyle: nil, vocabulary: [], corrections: [],
                      notation: notation, surrounding: surrounding, surroundingInPrompt: inPrompt)
    }

    private static func printJSON(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .prettyPrinted]) else { return }
        print(String(decoding: data, as: UTF8.self))
    }
}
