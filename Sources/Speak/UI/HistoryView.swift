import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var controller: DictationController
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var filter: HistoryFilter = .all
    @State private var search = ""
    @State private var confirmDeleteAll = false
    @State private var feedbackItem: HistoryItem?
    @State private var limit = 60
    @FocusState private var searchFocused: Bool

    private var items: [HistoryItem] {
        history.items.filter { item in
            filter.includes(item) && (search.isEmpty
                || item.output.localizedCaseInsensitiveContains(search)
                || item.rawTranscript.localizedCaseInsensitiveContains(search)
                || item.appName.localizedCaseInsensitiveContains(search))
        }
    }

    /// 日ごとにまとめる（新しい日が先）
    private var days: [(day: Date, items: [HistoryItem])] {
        let calendar = Calendar.current
        return Dictionary(grouping: items.prefix(limit)) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        Page {
            PageHeader(title: t("履歴", "History"),
                       subtitle: t("履歴はこの Mac の中だけに保存されます。保存期間: ", "History stays on this Mac only. Keep history: ") + settingsStore.settings.historyRetention.title) {
                MenuButton(trailing: true, entries: {
                    [.item(t("すべて削除…", "Delete all…"), symbol: "trash", destructive: true, enabled: !history.items.isEmpty) { confirmDeleteAll = true }]
                }) {
                    Image(systemName: "ellipsis").frame(width: 14)
                }
                .buttonStyle(.aside)
                .help(t("その他", "More"))
            }

            HStack(spacing: 12) {
                SegmentedControl(selection: $filter, options: HistoryFilter.allCases, title: { $0.title })
                Spacer()
                SearchField(placeholder: t("履歴を検索", "Search history"), text: $search, focus: $searchFocused)
                    .frame(width: 240)
            }

            if items.isEmpty {
                if history.items.isEmpty {
                    EmptyStateView(
                        symbol: "clock",
                        title: t("まだ履歴がありません", "No history yet"),
                        message: t("Fn キーを押して話してみましょう。結果がここに残ります。", "Press Fn and start speaking. Your dictations will appear here.")
                    )
                } else {
                    EmptyStateView(symbol: "magnifyingglass", title: t("見つかりませんでした", "No results"),
                                   message: t("検索語や絞り込みを変えてみてください。", "Try a different search or filter."))
                }
            } else {
                ForEach(days, id: \.day) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayTitle(day.day)).font(.ui(14, .medium)).foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text(t("\(day.items.count) 件", "\(day.items.count) items"))
                                .font(.ui(12).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        SettingsGroup {
                            ForEach(day.items) { item in
                                HistoryRow(item: item, retrying: controller.retrying.contains(item.id),
                                           onFeedback: { feedbackItem = item })
                            }
                        }
                    }
                }
                if items.count > limit {
                    Button(t("さらに表示", "Show more")) { limit += 60 }
                        .buttonStyle(.aside)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: filter) { limit = 60 }
        .onChange(of: search) { limit = 60 }
        .confirmationDialog(t("すべての履歴を削除しますか？", "Delete all history?"), isPresented: $confirmDeleteAll) {
            Button(t("すべて削除", "Delete all"), role: .destructive) { history.deleteAll() }
        } message: {
            Text(t("保存した音声も削除されます。元に戻せません。", "Saved audio is deleted too. This cannot be undone."))
        }
        .sheet(item: $feedbackItem) { item in
            FeedbackSheet(item: item)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return t("今日", "Today") }
        if calendar.isDateInYesterday(day) { return t("昨日", "Yesterday") }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current == .en ? "en_US" : "ja_JP")
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: Date())
        f.setLocalizedDateFormatFromTemplate(sameYear ? "MMMdEEE" : "yMMMdEEE")
        return f.string(from: day)
    }
}

struct HistoryRow: View {
    var item: HistoryItem
    var retrying: Bool
    var onFeedback: () -> Void
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var controller: DictationController
    @State private var hovering = false
    @State private var showRaw = false
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(item.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.ui(12).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 38, alignment: .leading)
                .padding(.top, 1.5)

            VStack(alignment: .leading, spacing: 8) {
                if item.mode == .ask, !item.rawTranscript.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "quote.opening").font(.system(size: 9, weight: .bold))
                        Text(item.rawTranscript).lineLimit(2)
                    }
                    .font(.ui(12.5))
                    .foregroundStyle(Palette.textSecondary)
                }
                if item.status == .failed && item.output.isEmpty {
                    Text(item.errorMessage ?? "")
                        .font(.ui(13))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(3)
                } else {
                    Text(item.output)
                        .font(.ui(13.5))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(3)
                        .lineLimit(showRaw ? nil : 4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showRaw && !item.rawTranscript.isEmpty && item.mode != .ask {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("認識結果（整形前）", "Raw transcript"))
                            .font(.ui(11, .medium))
                            .foregroundStyle(Palette.textTertiary)
                        Text(item.rawTranscript)
                            .font(.ui(12.5))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hover))
                }
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(hovering ? Palette.hover.opacity(0.6) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var meta: some View {
        HStack(spacing: 6) {
            Image(systemName: item.mode.symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
            Text(item.mode.title)
            if !item.appName.isEmpty {
                Text("·")
                if let bundleID = item.appBundleID, AppIconCache.icon(bundleID) != nil {
                    AppIcon(bundleID: bundleID, size: 13)
                }
                Text(item.appName)
            }
            if let target = item.targetLanguage {
                Text("→ " + Languages.name(target))
            }
            if item.status == .failed {
                Badge(text: t("失敗", "Failed"), tone: .neutral, symbol: "exclamationmark")
            }
            if item.feedback != nil {
                Image(systemName: "bubble.left.fill").font(.system(size: 9))
                    .help(t("フィードバック済み", "Feedback sent"))
            }
        }
        .font(.ui(11.5))
        .foregroundStyle(Palette.textTertiary)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if retrying {
                ProgressView().controlSize(.small).padding(.horizontal, 5)
            }
            IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: t("コピー", "Copy")) {
                TextInserter.copyToClipboard(item.output.isEmpty ? item.rawTranscript : item.output)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { copied = false } }
            }
            IconButton(symbol: "bubble.left", help: t("フィードバック", "Feedback"), action: onFeedback)
            if item.audioFile != nil {
                IconButton(symbol: "arrow.clockwise", help: t("再処理", "Retry")) { controller.retry(item) }
                    .disabled(retrying)
            }
            MenuButton(trailing: true, entries: {
                var entries: [MenuEntry] = [
                    .item(showRaw ? t("認識結果を隠す", "Hide raw transcript") : t("認識結果を表示", "Show raw transcript"), symbol: "text.quote") {
                        withAnimation(.smooth(duration: 0.2)) { showRaw.toggle() }
                    },
                ]
                if item.audioFile != nil {
                    entries.append(.item(t("音声をダウンロード", "Download audio"), symbol: "arrow.down.circle") { downloadAudio() })
                }
                entries.append(.separator)
                entries.append(.item(t("削除", "Delete transcript"), symbol: "trash", destructive: true) { history.delete(item) })
                return entries
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t("その他", "More"))
        }
        .opacity(hovering || retrying || copied ? 1 : 0)
    }

    private func downloadAudio() {
        guard let url = item.audioURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "Speak-\(f.string(from: item.date)).wav"
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
    }
}

/// 出力の直し方を教えてもらう。直した単語は辞書に、直し方はパーソナライズに反映する。
struct FeedbackSheet: View {
    var item: HistoryItem
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var dictionary: DictionaryStore
    @EnvironmentObject var personalization: PersonalizationStore
    @Environment(\.dismiss) private var dismiss
    @State private var corrected = ""
    @State private var note = ""

    var body: some View {
        SheetLayout(title: t("フィードバック", "Feedback"),
                    subtitle: t("期待していた出力に直してください。直した単語は辞書に、直し方は今後の整形に反映されます。",
                                "Edit the output into what you expected. Corrected words go to your dictionary and the edit guides future output."),
                    width: 540) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: t("期待していた出力", "Expected output"))
                AsideTextEditor(text: $corrected, minHeight: 130)
            }
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: t("メモ（任意）", "Note (optional)"))
                AsideTextField(placeholder: t("例: 敬語にしてほしかった", "e.g. I wanted it more formal"), text: $note)
            }
        } buttons: {
            Spacer()
            Button(t("キャンセル", "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.aside)
            Button(t("送信", "Submit")) { submit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.aside(.primary))
        }
        .onAppear { corrected = item.output }
    }

    private func submit() {
        var updated = item
        let trimmed = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.feedback = note.isEmpty ? t("出力を修正", "Edited output") : note
        if !trimmed.isEmpty, trimmed != item.output {
            let before = Array(item.output)
            let after = Array(trimmed)
            if let edit = CorrectionDetector.diff(before, after),
               let learned = CorrectionDetector.learnedTerm(before: before, after: after, edit: edit) {
                dictionary.add(learned.term, source: .auto, replaced: learned.replaced)
            }
            personalization.addCorrection(Correction(original: String(item.output.prefix(300)), preferred: String(trimmed.prefix(300))))
            updated.output = trimmed
        }
        if !note.isEmpty {
            personalization.addCorrection(Correction(original: "(\(item.category.rawValue) output)", preferred: "User note: \(note)"))
        }
        history.update(updated)
        dismiss()
    }
}
