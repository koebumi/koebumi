import SwiftUI

/// 音声バーの上の札で、録音中の書き起こしの字をどう見せるか。
/// 書き起こしを始めたら末尾を薄くして虹を 2 回通し、届いたら変わった部分を虹で 1 回なでる。
/// 話し終えて最後の文が届いたら、AI で整えている間は全文にゆっくり虹を流す。
struct LiveTextStyle: Equatable {
    /// 札に出す文（長ければ先頭を「…」で省く）
    var shown: String
    /// shown のうち、光らせる部分の始まり（字の数）。光らせる部分は文の終わりまで続く。光らせないときは nil
    var markedFrom: Int?
    var effect: Effect

    enum Effect: Equatable {
        case none
        /// 書き起こし中。光らせる部分を薄くし、band が nil でなければ虹の帯を通す（0〜1 が帯の位置）
        case transcribing(band: Double?)
        /// 届いた字を虹でなでる。帯より前は普通の色、後ろは薄い色
        case arrived(band: Double)
        /// 札に初めて字が出た。待たせないよう字はすぐ普通の色で出し、虹を 1 回上に通す
        case appeared(band: Double)
        /// AI で整えている間、全文に虹を流す
        case polishing(band: Double)
    }

    /// 書き起こし中に虹が 1 回通る秒数と回数。届くまで 0.4〜1 秒なので、だいたい 1〜2 回通る
    static let passDuration: TimeInterval = 0.45
    static let passes = 2
    /// 届いた字を虹がなでる秒数
    static let arrivalDuration: TimeInterval = 0.65
    /// 最後の文が届いてから全文に虹を流し始めるまでの秒数（届いた字をなでる間は待つ）と、1 回の秒数
    static let polishDelay: TimeInterval = 0.7
    static let polishDuration: TimeInterval = 2.2
    /// 札に出す幅。全角の字を 2、半角の字を 1 と数える（日本語なら 50 字で 2 行に収まる）
    static let shownWidth = 100
    /// 書き起こし中に光らせる末尾の幅（全角 6 字）
    static let tailWidth = 12

    /// ある時点での見せ方
    static func at(_ now: Date, live: LiveTranscript, reduceMotion: Bool) -> LiveTextStyle {
        let chars = Array(flatten(live.text))
        let (shown, start) = visible(chars)
        // 「…」で省いた部分は光らせない
        func mark(_ from: Int) -> Int { (start > 0 ? 1 : 0) + max(0, from - start) }
        func since(_ date: Date) -> TimeInterval { max(0, now.timeIntervalSince(date)) }

        if !reduceMotion, let final = live.finalAt, since(final) >= polishDelay {
            let band = ((since(final) - polishDelay) / polishDuration).truncatingRemainder(dividingBy: 1)
            return LiveTextStyle(shown: shown, markedFrom: mark(0), effect: .polishing(band: band))
        }
        if let started = live.transcribingSince {
            let elapsed = since(started)
            let band = reduceMotion || elapsed >= passDuration * Double(passes) ? nil : (elapsed / passDuration).truncatingRemainder(dividingBy: 1)
            return LiveTextStyle(shown: shown, markedFrom: mark(tailStart(chars)), effect: .transcribing(band: band))
        }
        if !reduceMotion, let arrived = live.arrivedAt, since(arrived) < arrivalDuration {
            let changed = commonPrefix(Array(flatten(live.previous)), chars)
            if changed < chars.count {
                let t = since(arrived) / arrivalDuration
                let band = t * t * (3 - 2 * t)
                return LiveTextStyle(shown: shown, markedFrom: mark(changed), effect: live.previous.isEmpty ? .appeared(band: band) : .arrived(band: band))
            }
        }
        return LiveTextStyle(shown: shown, markedFrom: nil, effect: .none)
    }

    /// いま動いている光が止まる時刻。整えている間は止まらない（distantFuture）。動いていなければ nil
    static func animationEnd(live: LiveTranscript, reduceMotion: Bool) -> Date? {
        guard !reduceMotion else { return nil }
        if live.finalAt != nil { return .distantFuture }
        let ends = [live.transcribingSince?.addingTimeInterval(passDuration * Double(passes)),
                    live.arrivedAt?.addingTimeInterval(arrivalDuration)]
        return ends.compactMap { $0 }.max()
    }

    /// 改行は空白にして 1 続きの文にする
    static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    static func width(_ c: Character) -> Int { c.isASCII ? 1 : 2 }

    /// 長くなったら、最後に話したところだけを出す。札の幅で 2 行に収まるよう、全角の字を 2、半角の字を 1 と数えて limit までにする
    /// （日本語なら 50 字。英語は単語の途中で折り返さない分の余裕を取る）。start は出す部分が文のどこから始まるか
    static func visible(_ chars: [Character], limit: Int = shownWidth) -> (shown: String, start: Int) {
        guard chars.reduce(0, { $0 + width($1) }) > limit else { return (String(chars), 0) }
        var used = width("…")
        var start = chars.count
        while start > 0, used + width(chars[start - 1]) <= limit {
            used += width(chars[start - 1])
            start -= 1
        }
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        return ("…" + String(chars[start...]), start)
    }

    /// 書き起こし中に光らせる末尾の始まり。英語は語の途中で切らない
    static func tailStart(_ chars: [Character]) -> Int {
        func isWord(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "'") }
        var cut = chars.count
        var used = 0
        while cut > 0, used < tailWidth {
            used += width(chars[cut - 1])
            cut -= 1
        }
        while cut > 0, cut < chars.count, isWord(chars[cut - 1]), isWord(chars[cut]) { cut -= 1 }
        return cut
    }

    static func commonPrefix(_ a: [Character], _ b: [Character]) -> Int {
        var n = 0
        while n < a.count, n < b.count, a[n] == b[n] { n += 1 }
        return n
    }
}

extension EnvironmentValues {
    /// `--snapshot` で、札の光を決まった時点で止めて描く
    @Entry var liveTextNow: Date? = nil
}

/// 録音中の書き起こしを出す札の字。光が動いている間だけ毎フレーム描き直す
struct LiveTextCard: View {
    let live: LiveTranscript
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liveTextNow) private var fixedNow
    /// 光が止まった後にもう一度描いて、止まった見た目にする
    @State private var settled = Date.distantPast

    var body: some View {
        let now = fixedNow ?? max(settled, Date())
        let end = LiveTextStyle.animationEnd(live: live, reduceMotion: reduceMotion)
        let animating = fixedNow == nil && end.map { $0 > now } == true
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { context in
            let style = LiveTextStyle.at(animating ? context.date : now, live: live, reduceMotion: reduceMotion)
            Self.text(style)
                .textRenderer(RainbowTextRenderer(effect: style.effect))
                // 字が届くたびに古い字と新しい字を重ねて切り替えない（光で見せる）
                .contentTransition(.identity)
        }
        .task(id: live) {
            guard fixedNow == nil, let end, end < .distantFuture else { return }
            try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow) + 0.03))
            settled = Date()
        }
    }

    static func text(_ style: LiveTextStyle) -> Text {
        guard let from = style.markedFrom else { return Text(style.shown) }
        let chars = Array(style.shown)
        return Text(String(chars[..<from])) + Text(String(chars[from...])).customAttribute(LiveTextMark())
    }
}

/// 札の字のうち、光らせる部分の印
struct LiveTextMark: TextAttribute {}

/// 印の付いた字に、虹の帯を通して描く。帯は印の付いた字を読む順（行をまたいで）に通る
struct RainbowTextRenderer: TextRenderer {
    var effect: LiveTextStyle.Effect

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let marked = layout.flatMap { $0 }.filter { $0[LiveTextMark.self] != nil }
        let total = marked.reduce(0) { $0 + $1.typographicBounds.width }
        let colors = Colors(dark: context.environment.colorScheme == .dark)
        var offset: CGFloat = 0
        for line in layout {
            for run in line {
                guard run[LiveTextMark.self] != nil, total > 0, effect != .none else {
                    context.draw(run)
                    continue
                }
                let rect = run.typographicBounds.rect
                let shading = shading(for: rect, at: offset, of: total, colors: colors)
                context.drawLayer { layer in
                    layer.draw(run)
                    layer.blendMode = .sourceIn
                    layer.fill(Path(rect.insetBy(dx: -2, dy: -3)), with: shading)
                }
                offset += rect.width
            }
        }
    }

    /// 字の色と虹の色。ガラスの上の字の色（Palette.text）に合わせて、薄い字は透明度で作る
    private struct Colors {
        let ink: Color, dim: Color, mid: Color, rainbow: [Color]

        init(dark: Bool) {
            ink = Color(nsColor: NSColor(hex: dark ? 0xeceef0 : 0x202428))
            dim = ink.opacity(dark ? 0.42 : 0.38)
            mid = ink.opacity(dark ? 0.72 : 0.65)
            rainbow = (dark ? [0x7cc4ff, 0xc79bff, 0xff9ccf] : [0x2878ff, 0x8c46ff, 0xe13c8c]).map { Color(nsColor: NSColor(hex: $0)) }
        }
    }

    /// rect の字が、印の付いた字の offset から始まるとして、帯のどこにあたるかで色を決める
    private func shading(for rect: CGRect, at offset: CGFloat, of total: CGFloat, colors: Colors) -> GraphicsContext.Shading {
        // 帯の幅は、光らせる字の幅に対する割合
        let passed: Color, ahead: Color, band: Double?, ratio: CGFloat
        switch effect {
        case .none: return .color(colors.ink)
        case .transcribing(let b): (passed, ahead, band, ratio) = (colors.dim, colors.dim, b, 0.84)
        case .arrived(let b): (passed, ahead, band, ratio) = (colors.ink, colors.dim, b, 0.5)
        case .appeared(let b): (passed, ahead, band, ratio) = (colors.ink, colors.ink, b, 0.5)
        case .polishing(let b): (passed, ahead, band, ratio) = (colors.mid, colors.mid, b, 0.72)
        }
        guard let band else { return .color(passed) }
        let width = max(total * ratio, 36)
        // 帯を、字の手前（帯の右端が字の頭）から後ろ（帯の左端が字の終わり）まで動かす
        let start = rect.minX - offset - width + CGFloat(band) * (total + width)
        let gradient = Gradient(stops: [
            .init(color: passed, location: 0),
            .init(color: colors.rainbow[0], location: 0.3),
            .init(color: colors.rainbow[1], location: 0.5),
            .init(color: colors.rainbow[2], location: 0.7),
            .init(color: ahead, location: 1),
        ])
        return .linearGradient(gradient, startPoint: CGPoint(x: start, y: rect.midY), endPoint: CGPoint(x: start + width, y: rect.midY))
    }
}
