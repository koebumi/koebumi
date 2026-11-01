// IBM Granite Speech 5.0 の CTC の出力を文字にする。
// transformers（Apache License 2.0）の ParakeetTokenizer._decode と、tokenizer.json の decoder
// （▁ を空白に・ByteFallback・Fuse・先頭の空白を 1 つ削る）を Swift に移した。
// Copyright 2026 IBM and The HuggingFace Team. Licensed under the Apache License, Version 2.0.

import Foundation

struct GraniteSpeechTokenizer {
    /// id ごとのトークンの文字列
    let pieces: [String]
    /// 書き出さない特殊なトークン（<unk>・<|nospeech|>・言語の印など）
    let specialIds: Set<Int>
    /// CTC のブランク。パディングのトークン（<unk>、id 0）
    let blankId: Int

    init(pieces: [String], specialIds: Set<Int>, blankId: Int) {
        self.pieces = pieces
        self.specialIds = specialIds
        self.blankId = blankId
    }

    /// tokenizer.json と tokenizer_config.json から作る。ブランクは tokenizer_config.json の pad_token で決め、なければ fallbackBlankId。
    init(tokenizerJSON: Data, tokenizerConfigJSON: Data? = nil, fallbackBlankId: Int) throws {
        guard let root = try JSONSerialization.jsonObject(with: tokenizerJSON) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let vocab = model["vocab"] as? [String: Any] else {
            throw GraniteSpeechError.invalidTokenizer("tokenizer.json に model.vocab がない")
        }
        var ids: [String: Int] = [:]
        for (piece, id) in vocab {
            guard let id = (id as? NSNumber)?.intValue, id >= 0 else { continue }
            ids[piece] = id
        }
        var special = Set<Int>()
        for token in root["added_tokens"] as? [[String: Any]] ?? [] {
            guard let id = (token["id"] as? NSNumber)?.intValue, let content = token["content"] as? String else { continue }
            ids[content] = id
            if token["special"] as? Bool == true { special.insert(id) }
        }
        guard let maxId = ids.values.max() else { throw GraniteSpeechError.invalidTokenizer("語彙が空") }
        var pieces = [String](repeating: "", count: maxId + 1)
        for (piece, id) in ids { pieces[id] = piece }

        var blank = fallbackBlankId
        if let data = tokenizerConfigJSON,
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pad = config["pad_token"] as? String, let id = ids[pad] {
            blank = id
        }
        self.init(pieces: pieces, specialIds: special, blankId: blank)
    }

    /// フレームごとに選んだ id から文字にする。続く同じ id を 1 つにまとめ、ブランクを除いてから復号する（ParakeetTokenizer と同じ順）。
    func decodeCTC(_ frameIds: [Int]) -> String {
        decode(Self.collapse(frameIds, blankId: blankId))
    }

    /// 続く同じ id を 1 つにまとめてから、ブランクを除く。ブランクを挟んだ同じ id は 2 つ残る（「ああ」を書ける）。
    static func collapse(_ ids: [Int], blankId: Int) -> [Int] {
        var out: [Int] = []
        var previous: Int?
        for id in ids {
            if id != previous, id != blankId { out.append(id) }
            previous = id
        }
        return out
    }

    /// トークンの id から文字にする（skip_special_tokens=True と同じ）
    func decode(_ ids: [Int]) -> String {
        var text = ""
        var bytes: [UInt8] = []
        // <0xE3><0x81><0x82> のように続くバイトのトークンは、まとめて UTF-8 として読む。読めなければバイトの数だけ � にする
        func flushBytes() {
            guard !bytes.isEmpty else { return }
            if let s = String(bytes: bytes, encoding: .utf8) {
                text += s
            } else {
                text += String(repeating: "\u{FFFD}", count: bytes.count)
            }
            bytes.removeAll()
        }
        for id in ids where id >= 0 && id < pieces.count && !specialIds.contains(id) {
            let piece = pieces[id]
            if let byte = Self.byteValue(piece) {
                bytes.append(byte)
            } else {
                flushBytes()
                text += piece.replacingOccurrences(of: "\u{2581}", with: " ")
            }
        }
        flushBytes()
        // 単語の頭の ▁ から来た、先頭の空白を 1 つだけ削る
        if text.hasPrefix(" ") { text.removeFirst() }
        return text
    }

    /// "<0xE3>" の形のトークンなら、そのバイト
    static func byteValue(_ piece: String) -> UInt8? {
        let chars = Array(piece.utf8)
        guard chars.count == 6, piece.hasPrefix("<0x"), piece.hasSuffix(">") else { return nil }
        return UInt8(String(decoding: chars[3..<5], as: UTF8.self), radix: 16)
    }
}
