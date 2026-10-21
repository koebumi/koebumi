import Charts
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var stats: StatsStore
    @EnvironmentObject var personalization: PersonalizationStore
    @EnvironmentObject var navigation: Navigation
    @State private var showReport = false

    var body: some View {
        Page {
            PageHeader(eyebrow: Date().formatted(.dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: L10n.current == .en ? "en_US" : "ja_JP"))), title: greeting,
                       subtitle: t("どのアプリでも、話すだけで整った文章に。", "Speak in any app and get polished writing."))

            HeroDemo(shortcut: settingsStore.settings.dictateShortcuts.first)

            StatsStrip(items: [
                (t("入力した単語", "Words dictated"), "text.word.spacing", "\(stats.stats.totalWords)"),
                (t("節約した時間", "Time saved"), "hourglass", durationString(stats.timeSaved)),
                (t("平均 WPM", "Average WPM"), "speedometer", "\(stats.averageWPM)"),
                (t("連続日数", "Day streak"), "flame", "\(stats.streak)"),
            ])

            ActivityChart(days: stats.lastDays(30))

            SectionLabel(t("はじめに", "Start here"))
            HStack(alignment: .top, spacing: 12) {
                GuideCard(mode: .dictate,
                          text: t("押して話し、もう一度押して確定。押し続けて話し、離して確定もできます。",
                                  "Press, speak, press again. Or hold while speaking and release."),
                          shortcuts: settingsStore.settings.shortcuts(for: .dictate))
                GuideCard(mode: .translate,
                          text: t("話した内容を翻訳先の言語で入力します。翻訳先は音声バーで切り替えられます。",
                                  "Speak in your language and insert the translation. Switch targets on the voice bar."),
                          shortcuts: settingsStore.settings.shortcuts(for: .translate))
                GuideCard(mode: .ask,
                          text: t("選択したテキストを「もっと丁寧に」などと話して書き換え。選択なしなら質問に答えます。",
                                  "Select text and say how to change it, or ask anything without a selection."),
                          shortcuts: settingsStore.settings.shortcuts(for: .ask))
            }
            HStack(spacing: 6) {
                KeyCap(text: "Esc", compact: true)
                Text(t("でいつでもキャンセルできます", "cancels at any time"))
            }
            .font(.ui(12.5))
            .foregroundStyle(Palette.textTertiary)
            .padding(.horizontal, 16)
            .padding(.top, -8)

            SectionLabel(t("パーソナライズ", "Personalization"))
            SettingsGroup {
                SettingRow(title: settingsStore.settings.personalizationEnabled ? t("あなたの書き方を学習中", "Learning how you write") : t("パーソナライズはオフです", "Personalization is off"),
                           subtitle: t("話すほど、言い回しやアプリごとのトーンに合わせて整形します。学習するのは抽象的な傾向だけで、内容は保存しません。",
                                       "The more you speak, the more output matches your tone in each app. Only abstract patterns are learned, never your content.")) {
                    if settingsStore.settings.personalizationEnabled {
                        Button(t("レポートを見る", "View report")) { showReport = true }
                            .buttonStyle(.aside)
                    } else {
                        Button(t("スタイルを開く", "Open Style")) { navigation.go(.style) }
                            .buttonStyle(.aside)
                    }
                }
                if settingsStore.settings.personalizationEnabled {
                    RowContent {
                        HStack(spacing: 12) {
                            ProgressBar(value: personalization.progress)
                            Text("\(Int(personalization.progress * 100))%")
                                .font(.ui(12.5, .medium).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showReport) { PersonalizationReportView() }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return t("おはようございます", "Good morning")
        case 11..<18: return t("こんにちは", "Good afternoon")
        default: return t("こんばんは", "Good evening")
        }
    }

    private func durationString(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return t("\(minutes)分", "\(minutes) min") }
        return t("\(minutes / 60)時間\(minutes % 60)分", "\(minutes / 60)h \(minutes % 60)m")
    }
}

// MARK: - ヒーロー

/// 話した言葉が整った文章になる様子を見せる
private struct HeroDemo: View {
    var shortcut: Shortcut?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            AuroraBackground()
            VStack(spacing: 14) {
                MockVoiceBar(shortcut: shortcut)
                TransformCard()
            }
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 272)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.panelBorder))
    }
}

struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        MeshGradient(width: 3, height: 3, points: points, colors: colors)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
            }
    }

    private var points: [SIMD2<Float>] {
        let c: SIMD2<Float> = drift ? [0.64, 0.4] : [0.36, 0.6]
        return [
            [0, 0], [drift ? 0.6 : 0.4, 0], [1, 0],
            [0, drift ? 0.42 : 0.58], c, [1, drift ? 0.62 : 0.38],
            [0, 1], [drift ? 0.38 : 0.62, 1], [1, 1],
        ]
    }

    private var colors: [Color] {
        if scheme == .dark {
            return [
                Color(red: 0.13, green: 0.12, blue: 0.27), Color(red: 0.20, green: 0.13, blue: 0.33), Color(red: 0.10, green: 0.17, blue: 0.30),
                Color(red: 0.11, green: 0.20, blue: 0.33), Color(red: 0.16, green: 0.15, blue: 0.24), Color(red: 0.28, green: 0.14, blue: 0.30),
                Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.12, green: 0.16, blue: 0.25), Color(red: 0.10, green: 0.11, blue: 0.16),
            ]
        }
        return [
            Color(red: 0.86, green: 0.82, blue: 1.0), Color(red: 0.96, green: 0.84, blue: 0.97), Color(red: 1.0, green: 0.88, blue: 0.86),
            Color(red: 0.80, green: 0.90, blue: 1.0), Color(red: 0.97, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.80, blue: 0.92),
            Color(red: 0.90, green: 0.94, blue: 1.0), Color(red: 0.86, green: 0.88, blue: 1.0), Color(red: 0.94, green: 0.86, blue: 1.0),
        ]
    }
}

private struct MockVoiceBar: View {
    var shortcut: Shortcut?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 本物の音声バーと同じ、白黒の丸・声に合わせて伸びる線・ガラスの面にする
        HStack(spacing: 13) {
            SymbolBadge(symbol: Mode.dictate.symbol)
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
                VoiceDots(level: reduceMotion ? 0.5 : Self.speakingLevel(context.date.timeIntervalSinceReferenceDate), processing: false)
            }
            if let shortcut {
                ShortcutKeys(shortcut: shortcut, compact: true)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, shortcut == nil ? 24 : 10)
        .frame(height: 42)
        .modifier(BarSurface())
    }

    /// 話している風の音量。音節ごとに上下し、ときどき黙る
    private static func speakingLevel(_ time: TimeInterval) -> Float {
        let syllable = max(0, sin(time * 7.3)) * (0.55 + 0.45 * sin(time * 2.3 + 1))
        let phrase = sin(time * 0.9) > -0.35 ? 1.0 : 0.04
        return Float(min(1, syllable * phrase * 0.85 + 0.02))
    }
}

private struct TransformCard: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Text(t("話した言葉", "What you said"))
                .font(.ui(11, .medium))
                .foregroundStyle(Palette.textTertiary)
            Text(spoken)
                .font(.ui(13.5))
                .padding(.top, 6)
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                Text(t("フィラーと言い直しを整理", "Fillers and corrections removed"))
            }
            .font(.ui(11, .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, 14)
            TypingLine(text: t("明日の会議は4時にしてください。", "Let's meet at 4 PM tomorrow."))
                .padding(.top, 6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(width: 400, alignment: .leading)
        .background(shape.fill(Palette.panel.opacity(0.92)))
        .overlay(shape.strokeBorder(Palette.panelBorder))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    /// フィラーと言い直した部分に取り消し線を引く
    private var spoken: AttributedString {
        let parts: [(String, Bool)] = L10n.current == .en
            ? [("um so ", true), ("let's meet at ", false), ("three, no, ", true), ("four pm tomorrow", false)]
            : [("えーと、", true), ("明日の会議は", false), ("3時に、いや", true), ("4時にしてください", false)]
        var result = AttributedString()
        for (text, removed) in parts {
            var piece = AttributedString(text)
            piece.foregroundColor = removed ? Palette.textTertiary : Palette.textSecondary
            if removed { piece.strikethroughStyle = .single }
            result += piece
        }
        return result
    }
}

/// 整った文章が 1 文字ずつ入力されていく様子（7 秒ごとに繰り返す）
private struct TypingLine: View {
    var text: String
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = isSnapshot || reduceMotion
        TimelineView(.animation(minimumInterval: 1 / 20, paused: still)) { context in
            let characters = Array(text)
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7)
            let count = still ? characters.count : min(characters.count, max(0, Int((time - 0.9) / 0.055)))
            let typing = count < characters.count
            let caretOn = typing || Int(time * 2.2) % 2 == 0
            HStack(spacing: 2) {
                Text(String(characters.prefix(count)))
                    .font(.ui(15, .medium))
                    .foregroundStyle(Palette.text)
                Capsule()
                    .fill(Palette.text)
                    .frame(width: 2, height: 17)
                    .opacity(still ? 0 : (caretOn ? 1 : 0))
            }
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        }
    }
}

// MARK: - 統計

private struct StatsStrip: View {
    var items: [(label: String, symbol: String, value: String)]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                if i > 0 {
                    Rectangle().fill(Palette.divider).frame(width: 1).padding(.vertical, 16)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: items[i].symbol).font(.system(size: 11))
                        Text(items[i].label)
                    }
                    .font(.ui(12))
                    .foregroundStyle(Palette.textSecondary)
                    Text(items[i].value)
                        .font(.ui(26))
                        .tracking(-0.6)
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(shape.fill(Palette.card))
    }
}

private struct ActivityChart: View {
    var days: [(date: Date, words: Int)]
    @State private var grown = false
    @State private var hovered: Date?

    private var maxWords: Int { max(days.map(\.words).max() ?? 0, 1) }
    private var total: Int { days.reduce(0) { $0 + $1.words } }

    var body: some View {
        CardBox {
            HStack(alignment: .firstTextBaseline) {
                Text(t("過去 30 日", "Last 30 days")).font(.ui(14, .medium)).foregroundStyle(Palette.text)
                Spacer()
                Text(t("合計 \(total) 語", "\(total) words"))
                    .font(.ui(12.5).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
            }
            Chart {
                ForEach(days, id: \.date) { day in
                    // 日ごとの列（値がない日もリズムが見えるようにする）
                    BarMark(x: .value("Day", day.date, unit: .day), yStart: .value("Words", 0), yEnd: .value("Words", maxWords), width: .ratio(0.62))
                        .foregroundStyle(Palette.hover.opacity(0.75))
                        .clipShape(Capsule())
                    BarMark(x: .value("Day", day.date, unit: .day), yStart: .value("Words", 0),
                            yEnd: .value("Words", grown ? day.words : 0), width: .ratio(0.62))
                        .foregroundStyle(barStyle(day))
                        .clipShape(Capsule())
                }
                if let hovered, let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hovered) }) {
                    RuleMark(x: .value("Day", day.date, unit: .day))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.ui(10.5))
                                    .foregroundStyle(Palette.textSecondary)
                                Text(t("\(day.words) 語", "\(day.words) words"))
                                    .font(.ui(12, .medium).monospacedDigit())
                                    .foregroundStyle(Palette.text)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.panel))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.panelBorder))
                            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
                        }
                }
            }
            .chartXSelection(value: $hovered)
            .chartYScale(domain: 0...maxWords)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.ui(10.5))
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(height: 132)
            .padding(.top, 6)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { grown = true }
        }
    }

    private func barStyle(_ day: (date: Date, words: Int)) -> AnyShapeStyle {
        let highlighted = hovered.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? Calendar.current.isDateInToday(day.date)
        return AnyShapeStyle(Palette.inverse.opacity(highlighted ? 1 : 0.22))
    }
}

// MARK: - はじめに

/// 操作の説明カード。クリックするとショートカットの設定を開く。
private struct GuideCard: View {
    var mode: Mode
    var text: String
    var shortcuts: [Shortcut]
    @EnvironmentObject var navigation: Navigation
    @State private var hovering = false

    var body: some View {
        Button { navigation.go(.shortcuts) } label: { card }
            .buttonStyle(.plain)
            .help(t("ショートカットを変更", "Change shortcuts"))
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                SymbolBadge(symbol: mode.symbol, size: 30)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -3, y: hovering ? 0 : 3)
            }
            Text(mode.title)
                .font(.ui(14.5, .medium))
                .foregroundStyle(Palette.text)
                .padding(.top, 16)
            Text(text)
                .font(.ui(12.5))
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Spacer(minLength: 16)
            HStack(spacing: 6) {
                ForEach(shortcuts) { ShortcutKeys(shortcut: $0, compact: true) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .contentShape(shape)
        .background(shape.fill(hovering ? Palette.controlHover : Palette.card))
        .shadow(color: .black.opacity(hovering ? 0.07 : 0), radius: 12, y: 6)
        .offset(y: hovering ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
    }
}
