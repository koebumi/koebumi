import Combine
import Foundation
import NaturalLanguage

/// 累計の利用統計。履歴を消しても残る。
struct UsageStats: Codable, Equatable {
    var totalWords = 0
    var totalSeconds: Double = 0
    var sessions = 0
    var dailyWords: [String: Int] = [:]  // yyyy-MM-dd → 単語数
}

@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    private static let fileName = "stats.json"
    /// 「節約できた時間」の計算に使うタイピング速度（単語/分）
    static let typingWPM = 40.0

    @Published private(set) var stats = UsageStats()

    private init() {
        stats = Storage.load(UsageStats.self, from: Self.fileName) ?? UsageStats()
    }

    func record(words: Int, seconds: Double, date: Date = Date()) {
        stats.totalWords += words
        stats.totalSeconds += seconds
        stats.sessions += 1
        stats.dailyWords[Self.dayKey(date), default: 0] += words
        Storage.save(stats, to: Self.fileName)
    }

    var averageWPM: Int {
        guard stats.totalSeconds > 5 else { return 0 }
        return Int(Double(stats.totalWords) / (stats.totalSeconds / 60))
    }

    /// タイピングと比べて節約できた時間（秒）
    var timeSaved: Double {
        max(0, Double(stats.totalWords) / Self.typingWPM * 60 - stats.totalSeconds)
    }

    var streak: Int { Self.streak(days: Set(stats.dailyWords.filter { $0.value > 0 }.keys), today: Date()) }

    func lastDays(_ n: Int, now: Date = Date()) -> [(date: Date, words: Int)] {
        let cal = Calendar.current
        return (0..<n).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now)) else { return nil }
            return (d, stats.dailyWords[Self.dayKey(d)] ?? 0)
        }
    }

    nonisolated static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    nonisolated static func streak(days: Set<String>, today: Date) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: today)
        // 今日まだ使っていなくても、昨日まで続いていれば連続とみなす
        if !days.contains(dayKey(day)) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(dayKey(day)) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// 単語数を数える。日本語のように空白で区切らない言語も単語単位で数える。
    nonisolated static func wordCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text[range].contains(where: { $0.isLetter || $0.isNumber }) { count += 1 }
            return true
        }
        return count
    }
}
