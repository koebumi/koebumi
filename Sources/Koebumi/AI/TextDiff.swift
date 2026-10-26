import Foundation

/// 2 つの文の違い。履歴で、AI の整形が変えたところ（消した語と足した語）を見せるのに使う
enum TextDiff {
    enum Kind: Equatable { case same, removed, added }

    struct Segment: Equatable {
        var kind: Kind
        var text: String
    }

    /// old から new への違いを、同じ部分・消した部分・足した部分の並びにする。
    /// 言い換えで 1 文字だけ同じ字が残った箇所（「見ました」→「拝見しました」の「見」）は、前後の変更とまとめて読みやすくする
    static func segments(from old: String, to new: String) -> [Segment] {
        let a = Array(old), b = Array(new)
        var chunks: [(same: String?, removed: String, added: String)] = []
        var i = 0
        for (o, n) in CorrectionDetector.changes(a, b) {
            if i < o.lowerBound { chunks.append((String(a[i..<o.lowerBound]), "", "")) }
            chunks.append((nil, String(a[o]), String(b[n])))
            i = o.upperBound
        }
        if i < a.count { chunks.append((String(a[i...]), "", "")) }

        var merged: [(same: String?, removed: String, added: String)] = []
        var k = 0
        while k < chunks.count {
            let c = chunks[k]
            if let same = c.same, same.count <= 1, let last = merged.last, last.same == nil, k + 1 < chunks.count, chunks[k + 1].same == nil {
                let next = chunks[k + 1]
                merged[merged.count - 1] = (nil, last.removed + same + next.removed, last.added + same + next.added)
                k += 2
                continue
            }
            if c.same == nil, let last = merged.last, last.same == nil {
                merged[merged.count - 1] = (nil, last.removed + c.removed, last.added + c.added)
            } else {
                merged.append(c)
            }
            k += 1
        }

        return merged.flatMap { c -> [Segment] in
            if let same = c.same { return [Segment(kind: .same, text: same)] }
            return [Segment(kind: .removed, text: c.removed), Segment(kind: .added, text: c.added)].filter { !$0.text.isEmpty }
        }
    }
}
