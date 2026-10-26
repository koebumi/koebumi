import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    @EnvironmentObject var dictionary: DictionaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var filter: DictionaryFilter = .all
    @State private var search = ""
    @State private var showAdd = false
    @State private var editing: DictionaryEntry?
    @State private var importMessage: String?
    @FocusState private var searchFocused: Bool

    private var entries: [DictionaryEntry] {
        dictionary.entries.filter { e in
            let byFilter: Bool = switch filter {
            case .all: true
            case .auto: e.source == .auto
            case .manual: e.source == .manual
            }
            return byFilter && (search.isEmpty || e.term.localizedCaseInsensitiveContains(search)
                || (e.replaced ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        Page {
            PageHeader(title: t("辞書", "Dictionary"),
                       subtitle: t("人名・略語・専門用語を登録すると、認識と表記が正確になります。", "Add names, acronyms and jargon so they are recognized and spelled correctly.")) {
                HStack(spacing: 8) {
                    MenuButton(trailing: true, entries: {
                        [
                            .item(t("CSV を取り込む…", "Import CSV…"), symbol: "square.and.arrow.down") { importCSV() },
                            .item(t("CSV を書き出す…", "Export CSV…"), symbol: "square.and.arrow.up", enabled: !dictionary.entries.isEmpty) { exportCSV() },
                        ]
                    }) {
                        Image(systemName: "ellipsis").frame(width: 14)
                    }
                    .buttonStyle(.aside)
                    .help(t("その他", "More"))
                    Button {
                        showAdd = true
                    } label: {
                        Label(t("新しい単語", "New word"), systemImage: "plus")
                    }
                    .buttonStyle(.aside(.primary))
                }
            }

            SettingsGroup {
                ToggleRow(title: t("直した単語を自動で追加", "Add corrected words automatically"),
                          subtitle: t("入力してから 1 分以内に単語を直すと、その単語を辞書に追加します。", "When you fix a word within a minute of dictating, Koebumi adds it here."),
                          isOn: $settingsStore.settings.autoAddDictionary)
                if ClaudeSkillRow.claudeCodeUsed {
                    ClaudeSkillRow()
                }
            }

            if let importMessage {
                Callout(symbol: "checkmark", text: importMessage) {
                    IconButton(symbol: "xmark", help: t("閉じる", "Dismiss")) { withAnimation { self.importMessage = nil } }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 12) {
                SegmentedControl(selection: $filter, options: DictionaryFilter.allCases, title: { $0.title })
                Spacer()
                SearchField(placeholder: t("単語を検索", "Search words"), text: $search, focus: $searchFocused)
                    .frame(width: 240)
            }

            if entries.isEmpty {
                if dictionary.entries.isEmpty {
                    EmptyStateView(
                        symbol: "character.book.closed",
                        title: t("単語がありません", "No words yet"),
                        message: t("「新しい単語」から追加するか、入力後に単語を直すと自動で追加されます。", "Add words with “New word”, or correct a word after dictating to add it automatically.")
                    )
                } else {
                    EmptyStateView(symbol: "magnifyingglass", title: t("見つかりませんでした", "No results"),
                                   message: t("検索語や絞り込みを変えてみてください。", "Try a different search or filter."))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("\(entries.count) 語", "\(entries.count) words"))
                        .font(.ui(12).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 16)
                    SettingsGroup {
                        ForEach(entries) { entry in
                            DictionaryRow(entry: entry, onEdit: { editing = entry })
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddWordSheet(onImport: { count in announceImport(count) })
        }
        .sheet(item: $editing) { entry in
            EditWordSheet(entry: entry)
        }
    }

    private func announceImport(_ count: Int) {
        withAnimation(.smooth) { importMessage = t("\(count) 語を取り込みました", "Imported \(count) words") }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
            announceImport(dictionary.importCSV(text))
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "koebumi-dictionary.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? dictionary.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Claude Code にスキルを入れる行。入れると「このリポジトリの用語を Koebumi の辞書に入れて」と頼める（System/DictionarySkill.swift）
private struct ClaudeSkillRow: View {
    @State private var status = DictionarySkill.status(executable: DictionaryCommand.executablePath)
    @State private var failure: String?

    /// Claude Code を使っている Mac でだけ行を出す
    static var claudeCodeUsed: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude")
    }

    var body: some View {
        SettingRow(title: t("Claude Code から単語を追加", "Add words from Claude Code"), subtitle: subtitle) {
            switch status {
            case .installed:
                HStack(spacing: 8) {
                    Badge(text: t("入れてあります", "Installed"), tone: .neutral, symbol: "checkmark")
                    Button(t("外す", "Remove")) { perform { try DictionarySkill.uninstall() } }
                        .buttonStyle(.aside)
                }
            case .outdated:
                Button(t("スキルを更新", "Update skill")) { install() }
                    .buttonStyle(.aside(.primary))
            case .notInstalled:
                Button(t("スキルを入れる", "Install skill")) { install() }
                    .buttonStyle(.aside)
            case .foreign:
                EmptyView()
            }
        }
        .onAppear { status = DictionarySkill.status(executable: DictionaryCommand.executablePath) }
    }

    private var subtitle: String {
        if let failure { return t("スキルを書き出せませんでした: \(failure)", "Could not write the skill: \(failure)") }
        if status == .foreign {
            return t("~/.claude/skills に、Koebumi が入れたのではない同じ名前のスキル（\(DictionarySkill.name)）があります。",
                     "~/.claude/skills already has a skill named \(DictionarySkill.name) that Koebumi did not install.")
        }
        return t("スキルを入れると、Claude Code に「このリポジトリの用語を Koebumi の辞書に入れて」と頼めます。Claude Code は、用語と聞き取られ方の一覧を見せてから登録します。",
                 "With the skill installed, ask Claude Code to “add this repo’s terms to my Koebumi dictionary”. It shows you the terms and how they are heard before adding them.")
    }

    private func install() {
        perform { try DictionarySkill.install(executable: DictionaryCommand.executablePath) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        status = DictionarySkill.status(executable: DictionaryCommand.executablePath)
    }
}

struct DictionaryRow: View {
    var entry: DictionaryEntry
    var onEdit: () -> Void
    @EnvironmentObject var dictionary: DictionaryStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.term)
                    .font(.ui(13.5, .medium))
                    .foregroundStyle(Palette.text)
                if let replaced = entry.replaced, !replaced.isEmpty {
                    HStack(spacing: 5) {
                        Text(replaced).strikethrough()
                        Image(systemName: "arrow.right").font(.system(size: 8.5, weight: .semibold))
                        Text(entry.term)
                    }
                    .font(.ui(12))
                    .foregroundStyle(Palette.textTertiary)
                }
            }
            Spacer()
            HStack(spacing: 0) {
                IconButton(symbol: "pencil", help: t("編集", "Edit"), action: onEdit)
                IconButton(symbol: "trash", help: t("削除", "Delete")) { dictionary.delete(entry) }
            }
            .opacity(hovering ? 1 : 0)
            Badge(text: entry.source == .auto ? t("自動", "Auto") : t("手動", "Manual"),
                  tone: .neutral,
                  symbol: entry.source == .auto ? "sparkles" : nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 48)
        .background(hovering ? Palette.hover.opacity(0.6) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct AddWordSheet: View {
    var onImport: (Int) -> Void
    @EnvironmentObject var dictionary: DictionaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var heard = ""

    var body: some View {
        SheetLayout(title: t("新しい単語", "New word"),
                    subtitle: t("人名・製品名・略語など、正しく書いてほしい語を登録します。", "Add names, products or acronyms you want spelled exactly."),
                    width: 460) {
            AsideTextField(placeholder: t("単語またはフレーズ", "Word or phrase"), text: $term, onSubmit: add)
            HeardAsField(text: $heard, onSubmit: add)
            Text(t("CSV は 1 列目を単語、3 列目を聞き取られ方として読み込みます。", "CSV import reads the word from the first column and “heard as” from the third."))
                .font(.ui(12))
                .foregroundStyle(Palette.textTertiary)
        } buttons: {
            Button(t("CSV を取り込む…", "Import CSV…")) { importCSV() }
                .buttonStyle(.aside(.ghost))
            Spacer()
            Button(t("キャンセル", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.aside)
            Button(t("追加", "Add"), action: add)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.aside(.primary))
                .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dictionary.add(term, source: .manual, replaced: heard)
        dismiss()
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) {
            onImport(dictionary.importCSV(text))
            dismiss()
        }
    }
}

struct EditWordSheet: View {
    var entry: DictionaryEntry
    @EnvironmentObject var dictionary: DictionaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var heard = ""

    var body: some View {
        SheetLayout(title: t("単語を編集", "Edit word"), width: 460) {
            AsideTextField(placeholder: t("単語またはフレーズ", "Word or phrase"), text: $term, onSubmit: save)
            HeardAsField(text: $heard, onSubmit: save)
        } buttons: {
            Spacer()
            Button(t("キャンセル", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.aside)
            Button(t("保存", "Save"), action: save)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.aside(.primary))
        }
        .onAppear {
            term = entry.term
            heard = entry.replaced ?? ""
        }
    }

    private func save() {
        dictionary.update(entry, term: term, replaced: heard)
        dismiss()
    }
}

/// 音声認識での聞き取られ方の入力欄（Apple の音声認識は英語の語をカタカナで書くため、その表記を登録する）
struct HeardAsField: View {
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsideTextField(placeholder: t("聞き取られ方（任意）例: クロードコード", "Heard as (optional), e.g. cloud code"), text: $text, onSubmit: onSubmit)
            Text(t("認識結果にこの表記が出てきたら、上の単語に置き換えます。カンマで区切って複数書けます。",
                   "When the transcript contains this, Koebumi replaces it with the word above. Separate several with commas."))
                .font(.ui(12))
                .foregroundStyle(Palette.textTertiary)
        }
    }
}
