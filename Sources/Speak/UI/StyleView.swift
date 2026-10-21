import AppKit
import SwiftUI

struct StyleView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var personalization: PersonalizationStore
    @EnvironmentObject var controller: DictationController
    @State private var showReport = false
    @State private var confirmReset = false

    var body: some View {
        Page {
            PageHeader(title: t("スタイル", "Style"),
                       subtitle: t("アプリに合わせてトーンを変え、あなたの書き方を学習します。", "Adapt the tone to each app and learn how you write."))

            SettingsGroup {
                ToggleRow(title: t("パーソナライズ", "Personalization"),
                          subtitle: settingsStore.settings.personalizationEnabled
                              ? t("\(PersonalizationStore.batchSize) 回話すごとに、丁寧さ・詳しさ・言い回しの傾向を学習します。内容そのものは保存しません。",
                                  "Every \(PersonalizationStore.batchSize) dictations Speak learns your formality, detail and phrasing. Your content is never stored.")
                              : t("オフの間は文体を学習せず、標準のトーンで整形します。", "While off, Speak stops learning and uses standard phrasing."),
                          isOn: $settingsStore.settings.personalizationEnabled)
                if settingsStore.settings.personalizationEnabled {
                    RowContent {
                        HStack(spacing: 12) {
                            ProgressBar(value: personalization.progress)
                            Text("\(Int(personalization.progress * 100))%")
                                .font(.ui(12.5, .medium).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                        HStack(spacing: 8) {
                            Button(t("レポートを見る", "View report")) { showReport = true }
                                .buttonStyle(.aside)
                            Button(t("今すぐ学習", "Learn now")) { controller.runStyleAnalysisNow() }
                                .buttonStyle(.aside)
                                .disabled(personalization.pendingCount == 0 || personalization.isAnalyzing)
                            if personalization.isAnalyzing { ProgressView().controlSize(.small) }
                            Spacer()
                            Button(t("学習をリセット…", "Reset learning…")) { confirmReset = true }
                                .buttonStyle(.aside(.ghost))
                        }
                        if let error = personalization.lastError {
                            HStack(alignment: .top, spacing: 6) {
                                SymbolBadge(symbol: "exclamationmark", size: 14)
                                Text(error).fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.ui(12))
                            .foregroundStyle(Palette.text)
                        }
                    }
                }
            }

            SectionLabel(t("アプリごとのトーン", "Tone per app"),
                         subtitle: t("入力先のアプリの種類に合わせて言葉づかいを変えます。「自動」は学習した文体に合わせます。",
                                     "Speak adjusts wording to the kind of app you are typing in. “Auto” follows your learned style."))
            SettingsGroup {
                ForEach(AppCategory.allCases) { category in
                    HStack(spacing: 12) {
                        IconTile(symbol: category.symbol, tint: Palette.textSecondary, size: 28)
                        Text(category.title)
                            .font(.ui(13.5, .medium))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        PopupPicker(selection: presetBinding(category), options: StylePreset.allCases, title: { $0.title }, minWidth: 150)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }

            ChatPunctuationSection()

            if writesJapanese { JapaneseNotationSection() }

            AppAssignmentSection()
        }
        .sheet(isPresented: $showReport) { PersonalizationReportView() }
        .confirmationDialog(t("学習した文体をリセットしますか？", "Reset learned style?"), isPresented: $confirmReset) {
            Button(t("リセット", "Reset"), role: .destructive) { personalization.reset() }
        }
    }

    private var writesJapanese: Bool {
        let s = settingsStore.settings
        return (s.dictationLanguages + s.translationTargets).contains { $0.hasPrefix("ja") }
    }

    private func presetBinding(_ category: AppCategory) -> Binding<StylePreset> {
        Binding(
            get: { settingsStore.settings.style(for: category) },
            set: { settingsStore.settings.categoryStyles[category.rawValue] = $0 }
        )
    }
}

/// 日本語の表記ルール。下の例文で、いまの設定での仕上がりを確かめられる。
struct JapaneseNotationSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    private static let sample = "お手数ですが、iPhone の設定を確認して下さい。明日出来る事から進めてもいいですか。"

    var body: some View {
        let notation = settingsStore.settings.japaneseNotation
        SectionLabel(t("日本語の表記", "Japanese notation"),
                     subtitle: t("入力する直前に、AI を使わない決まった処理でそろえます。AI の言い回しには影響しません。",
                                 "Applied right before typing by fixed rules, not by the AI, so the AI's wording is unaffected."))
        SettingsGroup {
            SettingRow(title: t("句読点", "Punctuation")) {
                PopupPicker(selection: $settingsStore.settings.japaneseNotation.punctuation, options: JapanesePunctuation.allCases,
                            title: { $0.title }, minWidth: 150)
            }
            SettingRow(title: t("英単語の前後の空白", "Spaces around English words")) {
                PopupPicker(selection: $settingsStore.settings.japaneseNotation.latinSpacing, options: LatinSpacing.allCases,
                            title: { $0.title }, minWidth: 150)
            }
            ToggleRow(title: t("補助動詞・形式名詞をひらがなで書く", "Write auxiliary verbs and formal nouns in hiragana"),
                      subtitle: t("〜して下さい → 〜してください、出来る → できる、する事 → すること。「資料を下さい」のような本来の意味の語は変えません。",
                                  "して下さい → してください, 出来る → できる, する事 → すること. Content words stay in kanji."),
                      isOn: $settingsStore.settings.japaneseNotation.hiraganaForms)
            ToggleRow(title: t("疑問文の文末を「？」にする", "End questions with ？"),
                      subtitle: t("〜ですか。・〜ますか。・〜でしょうか。を「？」で終えます。「今何時」のように語尾で疑問とわからない文は、AI の整形に任せます。",
                                  "〜ですか。, 〜ますか。 and 〜でしょうか。 end with ？. Questions without such endings are left to AI cleanup."),
                      isOn: $settingsStore.settings.japaneseNotation.questionMark)
            ExampleRow(label: t("例", "Example"), text: JapaneseFormatter.apply(Self.sample, notation: notation))
        }
    }
}

/// チャットでの句読点。話す言語にかかわらず使う。下の例文で、話す言語ごとの仕上がりを確かめられる。
struct ChatPunctuationSection: View {
    @EnvironmentObject var settingsStore: SettingsStore
    /// 話す言語か翻訳先にある言語の例文を出す（どれもなければ英語）
    private static let samples: [(language: String, text: String)] = [
        ("ja", "はい、了解です。資料は明日の朝に送ります。"),
        ("en", "Sure, sounds good. I'll send the file tomorrow morning."),
        ("zh", "好的，没问题。我明天早上发给你。"),
        ("ko", "네, 알겠습니다. 내일 아침에 보낼게요."),
    ]

    var body: some View {
        let s = settingsStore.settings
        SectionLabel(t("チャット", "Chat"),
                     subtitle: t("「チャット」に分類したアプリ（Slack・LINE など）に入力するときの書き方です。",
                                 "How Speak writes in apps in the Chat category (Slack, LINE…)."))
        SettingsGroup {
            SettingRow(title: t("句読点", "Punctuation"),
                       subtitle: t("どの言語にも適用します。「？」「！」と、1,000・3.5・a.m. のような数字と略語の「,」「.」は残します。",
                                   "Applies to every language. ? and !, and the , and . in numbers and abbreviations like 1,000, 3.5 and a.m. stay.")) {
                PopupPicker(selection: $settingsStore.settings.chatPunctuation, options: ChatPunctuation.allCases,
                            title: { $0.title }, minWidth: 190)
            }
            if s.chatPunctuation != .keep {
                ForEach(examples(s), id: \.language) { sample in
                    // 入力するときと同じく、日本語の表記ルールの後に句読点を消す
                    ExampleRow(label: Languages.name(sample.language),
                               text: s.chatPunctuation.apply(JapaneseFormatter.apply(sample.text, notation: s.japaneseNotation)))
                }
            }
        }
    }

    private func examples(_ s: AppSettings) -> [(language: String, text: String)] {
        let written = Set((s.dictationLanguages + s.translationTargets).map(Languages.isoCode))
        let shown = Self.samples.filter { written.contains($0.language) }
        return shown.isEmpty ? Self.samples.filter { $0.language == "en" } : shown
    }
}

/// 設定での仕上がりを見せる例文の行
private struct ExampleRow: View {
    let label: String
    let text: String

    var body: some View {
        RowContent {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // 見出しの長さが違っても、文の書き出しをそろえる
                Text(label)
                    .font(.ui(12, .medium))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(minWidth: 64, alignment: .leading)
                Text(text)
                    .font(.ui(13))
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// アプリをどの種類として扱うかの上書き
struct AppAssignmentSection: View {
    @EnvironmentObject var settingsStore: SettingsStore

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        SectionLabel(title: t("アプリの種類", "App categories"),
                     subtitle: t("自動判定が合わないアプリは、ここで種類を指定できます。", "If an app is detected wrongly, set its category here.")) {
            MenuButton(trailing: true, entries: {
                let apps = runningApps.filter { app in
                    guard let id = app.bundleIdentifier else { return false }
                    return settingsStore.settings.appCategoryOverrides[id] == nil
                }
                if apps.isEmpty { return [.item(t("追加できるアプリはありません", "No apps to add"), enabled: false) {}] }
                return [.header(t("起動中のアプリ", "Running apps"))] + apps.map { app in
                    .item(app.localizedName ?? app.bundleIdentifier ?? "?") {
                        if let id = app.bundleIdentifier {
                            settingsStore.settings.appCategoryOverrides[id] = AppContext.classify(bundleID: id, windowTitle: nil)
                        }
                    }
                }
            }) {
                Label(t("アプリを追加", "Add app"), systemImage: "plus")
            }
            .buttonStyle(.aside(compact: true))
        }
        let overrides = settingsStore.settings.appCategoryOverrides.sorted { $0.key < $1.key }
        if overrides.isEmpty {
            EmptyStateView(symbol: "square.grid.2x2", title: t("指定したアプリはありません", "No apps assigned"),
                           message: t("「アプリを追加」から起動中のアプリを選べます。", "Pick a running app with “Add app”."))
        } else {
            SettingsGroup {
                ForEach(overrides, id: \.key) { bundleID, _ in
                    HStack(spacing: 12) {
                        AppIcon(bundleID: bundleID)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName(bundleID)).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                            Text(bundleID).font(.ui(11.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        }
                        Spacer()
                        PopupPicker(selection: Binding(
                            get: { settingsStore.settings.appCategoryOverrides[bundleID] ?? .other },
                            set: { settingsStore.settings.appCategoryOverrides[bundleID] = $0 }
                        ), options: AppCategory.allCases, title: { $0.title }, symbol: { $0.symbol }, minWidth: 150)
                        IconButton(symbol: "minus.circle", help: t("削除", "Remove")) {
                            settingsStore.settings.appCategoryOverrides.removeValue(forKey: bundleID)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

struct PersonalizationReportView: View {
    @EnvironmentObject var personalization: PersonalizationStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetLayout(title: t("パーソナライズのレポート", "Personalization report"),
                    subtitle: t("学習済みサンプル: \(personalization.profile.samplesAnalyzed)　学習待ち: \(personalization.pendingCount)",
                                "Samples learned: \(personalization.profile.samplesAnalyzed)   Waiting: \(personalization.pendingCount)"),
                    width: 540) {
            HStack(spacing: 12) {
                ProgressBar(value: personalization.progress)
                Text("\(Int(personalization.progress * 100))%")
                    .font(.ui(12.5, .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }
            if personalization.profile.general.isEmpty && personalization.profile.categories.isEmpty {
                EmptyStateView(symbol: "person.crop.circle.badge.questionmark", title: t("まだ学習していません", "Nothing learned yet"),
                               message: t("\(PersonalizationStore.batchSize) 回ほど話すと最初の学習が行われます。",
                                          "The first update happens after about \(PersonalizationStore.batchSize) dictations."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !personalization.profile.general.isEmpty {
                            CardBox(padding: 16) {
                                Text(t("全体の傾向", "Overall")).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                                Text(personalization.profile.general)
                                    .font(.ui(13))
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineSpacing(2.5)
                            }
                        }
                        ForEach(AppCategory.allCases) { category in
                            if let p = personalization.profile.categories[category.rawValue] {
                                CardBox(padding: 16) {
                                    Label(category.title, systemImage: category.symbol)
                                        .font(.ui(13.5, .medium))
                                        .foregroundStyle(Palette.text)
                                    scale(t("カジュアル", "Casual"), t("フォーマル", "Formal"), p.formality)
                                    scale(t("簡潔", "Concise"), t("詳細", "Detailed"), p.verbosity)
                                    if !p.notes.isEmpty {
                                        Text(p.notes).font(.ui(12.5)).foregroundStyle(Palette.textSecondary).lineSpacing(2)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
            if let date = personalization.profile.updatedAt {
                Text(t("最終更新: ", "Last updated: ") + relativeDate(date))
                    .font(.ui(12))
                    .foregroundStyle(Palette.textTertiary)
            }
        } buttons: {
            Spacer()
            Button(t("閉じる", "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.aside(.primary))
        }
    }

    private func scale(_ left: String, _ right: String, _ value: Int) -> some View {
        HStack(spacing: 10) {
            Text(left).frame(width: 64, alignment: .leading)
            ScaleTrack(value: Double(value) / 100)
            Text(right).frame(width: 64, alignment: .trailing)
        }
        .font(.ui(11.5))
        .foregroundStyle(Palette.textSecondary)
    }
}

/// 両端のあいだのどこにいるかを点で示す
private struct ScaleTrack: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.meter).frame(height: 4)
                Circle()
                    .fill(Palette.inverse)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Palette.card, lineWidth: 2))
                    .offset(x: (geo.size.width - 10) * min(max(value, 0), 1))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
    }
}
