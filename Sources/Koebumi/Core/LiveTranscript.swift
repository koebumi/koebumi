import Foundation

/// 録音中に書き起こした内容と、音声バーの札で字を光らせるための時刻
struct LiveTranscript: Equatable {
    /// ここまでに話した内容の書き起こし
    var text = ""
    /// 1 つ前に届いた書き起こし。変わった部分を見分けるのに使う
    var previous = ""
    /// text が届いた時刻
    var arrivedAt: Date?
    /// 次の書き起こしを始めた時刻。届いたら nil に戻す
    var transcribingSince: Date?
    /// 話し終えた後、残りまで書き起こした最後の文が届いた時刻
    var finalAt: Date?

    mutating func receive(_ event: LiveTranscriptEvent, at now: Date) {
        switch event {
        case .transcribing:
            transcribingSince = now
        case .partial(let text):
            update(text, at: now)
        case .final(let text):
            update(text, at: now)
            finalAt = now
        }
    }

    /// 書き起こし直しても同じ文なら、届いた時刻は変えない（光らせる部分がない）
    private mutating func update(_ newText: String, at now: Date) {
        transcribingSince = nil
        guard newText != text else { return }
        previous = text
        text = newText
        arrivedAt = now
    }
}
