import Foundation

enum SubtitleParser {
    enum ParserError: Error, LocalizedError {
        case unsupportedEncoding
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupportedEncoding:
                "字幕文件编码无法识别"
            case .empty:
                "字幕文件没有可用内容"
            }
        }
    }

    static func parse(url: URL) throws -> [SubtitleCue] {
        let data = try Data(contentsOf: url)
        let text = decode(data: data)
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParserError.unsupportedEncoding
        }

        let ext = url.pathExtension.lowercased()
        let cues: [SubtitleCue]
        switch ext {
        case "srt":
            cues = parseSRT(text)
        case "vtt":
            cues = parseWebVTT(text)
        case "lrc":
            cues = parseLRC(text)
        case "ass", "ssa":
            cues = parseASS(text)
        default:
            cues = parseSRT(text) + parseWebVTT(text) + parseLRC(text) + parseASS(text)
        }

        let sorted = cues.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { throw ParserError.empty }
        return sorted.enumerated().map { offset, cue in
            SubtitleCue(index: offset + 1, start: cue.start, end: cue.end, text: cue.text)
        }
    }

    private static func decode(data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text.removingUTF8BOM()
        }
        let encodings: [String.Encoding] = [.utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1, .windowsCP1252]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text.removingUTF8BOM()
            }
        }
        return nil
    }

    private static func parseSRT(_ source: String) -> [SubtitleCue] {
        normalizedBlocks(source).compactMap { block in
            let lines = block.lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let timeLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let pieces = lines[timeLineIndex].components(separatedBy: "-->")
            guard pieces.count == 2,
                  let start = parseTimestamp(pieces[0]),
                  let end = parseTimestamp(pieces[1]),
                  end > start else {
                return nil
            }

            let text = lines.dropFirst(timeLineIndex + 1)
                .map(cleanSubtitleMarkup)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SubtitleCue(index: 0, start: start, end: end, text: text)
        }
    }

    private static func parseWebVTT(_ source: String) -> [SubtitleCue] {
        let stripped = source
            .replacingOccurrences(of: "WEBVTT", with: "")
            .replacingOccurrences(of: "\u{feff}", with: "")
        return parseSRT(stripped)
    }

    private static func parseLRC(_ source: String) -> [SubtitleCue] {
        let timestampPattern = #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: timestampPattern) else { return [] }
        var timedLines: [(TimeInterval, String)] = []

        for line in source.lines {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            let matches = regex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let textRangeStart = matches.last.map { $0.range.location + $0.range.length } ?? 0
            let text = nsLine.substring(from: textRangeStart)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minute = number(in: nsLine, range: match.range(at: 1)),
                      let second = number(in: nsLine, range: match.range(at: 2)) else {
                    continue
                }
                let fractionText = string(in: nsLine, range: match.range(at: 3)) ?? "0"
                let scale = pow(10, Double(fractionText.count))
                let fraction = (Double(fractionText) ?? 0) / scale
                timedLines.append((Double(minute * 60 + second) + fraction, text))
            }
        }

        let sorted = timedLines.sorted { $0.0 < $1.0 }
        return sorted.enumerated().map { index, item in
            let nextStart = index + 1 < sorted.count ? sorted[index + 1].0 : item.0 + 4
            return SubtitleCue(index: 0, start: item.0, end: max(item.0 + 1.5, nextStart), text: item.1)
        }
    }

    private static func parseASS(_ source: String) -> [SubtitleCue] {
        source.lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("dialogue:") else { return nil }
            let payload = String(trimmed.dropFirst("Dialogue:".count))
            let parts = payload.split(separator: ",", maxSplits: 9, omittingEmptySubsequences: false)
            guard parts.count >= 10,
                  let start = parseTimestamp(String(parts[1])),
                  let end = parseTimestamp(String(parts[2])),
                  end > start else {
                return nil
            }

            let text = cleanSubtitleMarkup(String(parts[9]))
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SubtitleCue(index: 0, start: start, end: end, text: text)
        }
    }

    private static func normalizedBlocks(_ source: String) -> [String] {
        source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let clean = raw
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .first(where: { !$0.isEmpty })?
            .replacingOccurrences(of: ",", with: ".")
        guard let clean else { return nil }

        let pieces = clean.split(separator: ":")
        guard pieces.count >= 2 else { return nil }

        let secondsPiece = pieces.last ?? "0"
        let secondParts = secondsPiece.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let seconds = Double(secondParts.first ?? "0") else { return nil }

        let fraction: Double
        if secondParts.count > 1 {
            let fractionText = String(secondParts[1])
            fraction = (Double(fractionText) ?? 0) / pow(10, Double(fractionText.count))
        } else {
            fraction = 0
        }

        let minutes = Double(pieces.dropLast().last ?? "0") ?? 0
        let hours = pieces.count >= 3 ? Double(pieces.dropLast(2).last ?? "0") ?? 0 : 0
        return hours * 3600 + minutes * 60 + seconds + fraction
    }

    private static func cleanSubtitleMarkup(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\{[^}]+\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(in string: NSString, range: NSRange) -> Int? {
        guard let text = self.string(in: string, range: range) else { return nil }
        return Int(text)
    }

    private static func string(in string: NSString, range: NSRange) -> String? {
        guard range.location != NSNotFound else { return nil }
        return string.substring(with: range)
    }
}

private extension String {
    var lines: [String] {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    func removingUTF8BOM() -> String {
        replacingOccurrences(of: "\u{feff}", with: "")
    }
}
