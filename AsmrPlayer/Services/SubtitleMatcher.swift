import Foundation

enum SubtitleMatcher {
    struct Match {
        let url: URL
        let score: Int
        let reason: String
    }

    static func rankedMatches(for mediaURL: URL, subtitles: [URL], preferredLanguage: SubtitleLanguage = .auto) -> [Match] {
        subtitles.compactMap { subtitleURL -> Match? in
            let score = score(mediaURL: mediaURL, subtitleURL: subtitleURL) + languageBonus(for: subtitleURL, language: preferredLanguage)
            guard score >= 40 else { return nil }
            return Match(url: subtitleURL, score: score, reason: reason(for: score))
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    static func bestMatch(for mediaURL: URL, subtitles: [URL]) -> Match? {
        rankedMatches(for: mediaURL, subtitles: subtitles).first
    }

    private static func languageBonus(for subtitleURL: URL, language: SubtitleLanguage) -> Int {
        guard language != .auto else { return 0 }
        let name = subtitleURL.deletingPathExtension().lastPathComponent.lowercased()
        return language.filenameHints.contains { name.contains($0.lowercased()) } ? 18 : 0
    }

    private static func score(mediaURL: URL, subtitleURL: URL) -> Int {
        let mediaName = mediaURL.deletingPathExtension().lastPathComponent
        let subtitleName = subtitleURL.deletingPathExtension().lastPathComponent
        let mediaFingerprint = fingerprint(mediaName)
        let subtitleFingerprint = fingerprint(subtitleName)
        var score = 0

        if mediaURL.deletingLastPathComponent().standardizedFileURL == subtitleURL.deletingLastPathComponent().standardizedFileURL {
            score += 28
        }

        if mediaFingerprint.normalized == subtitleFingerprint.normalized {
            score += 70
        } else if subtitleFingerprint.normalized.hasPrefix(mediaFingerprint.normalized) ||
                    mediaFingerprint.normalized.hasPrefix(subtitleFingerprint.normalized) {
            score += 48
        }

        let sharedIDs = mediaFingerprint.workIDs.intersection(subtitleFingerprint.workIDs)
        if !sharedIDs.isEmpty {
            score += 38
        }

        let sharedTracks = mediaFingerprint.trackNumbers.intersection(subtitleFingerprint.trackNumbers)
        if !sharedTracks.isEmpty {
            score += 16
        } else if !mediaFingerprint.trackNumbers.isEmpty,
                  !subtitleFingerprint.trackNumbers.isEmpty,
                  !sharedIDs.isEmpty {
            score -= 18
        }

        let tokenScore = tokenOverlapScore(mediaFingerprint.tokens, subtitleFingerprint.tokens)
        score += tokenScore

        let baseOverlap = commonPrefixScore(mediaFingerprint.normalized, subtitleFingerprint.normalized)
        score += baseOverlap

        if mediaFingerprint.normalized.contains(subtitleFingerprint.normalized) || subtitleFingerprint.normalized.contains(mediaFingerprint.normalized) {
            score += 18
        }

        if looksLikeSubtitleOnly(subtitleFingerprint.tokens) {
            score -= 20
        }

        return score
    }

    private static func reason(for score: Int) -> String {
        if score >= 100 { return "同名或同作品编号" }
        if score >= 80 { return "文件名高度相似" }
        return "文件名相似"
    }

    private static func fingerprint(_ name: String) -> Fingerprint {
        let lowercased = name.lowercased()
        let workIDs = Set(matches(in: lowercased, pattern: #"[a-z]{0,2}j\d{5,8}"#))
        let trackNumbers = Set(matches(in: lowercased, pattern: #"(?<!\d)(?:track|tr|part|pt|第)?0?(\d{1,3})(?:轨|話|话|章)?(?!\d)"#))

        let cleaned = lowercased
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^\)]*\)|\{[^\}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9\u{4e00}-\u{9fff}]+"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .filter { !noiseTokens.contains($0) }

        let tokens = Set(cleaned)
        return Fingerprint(
            normalized: cleaned.joined(),
            tokens: tokens,
            workIDs: workIDs,
            trackNumbers: trackNumbers
        )
    }

    private static func tokenOverlapScore(_ lhs: Set<String>, _ rhs: Set<String>) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Int((Double(intersection) / Double(union) * 34).rounded())
    }

    private static func commonPrefixScore(_ lhs: String, _ rhs: String) -> Int {
        let maxLength = min(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0 }
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        var matched = 0
        while matched < maxLength, lhsChars[matched] == rhsChars[matched] {
            matched += 1
        }
        guard matched >= 3 else { return 0 }
        return min(20, matched * 2)
    }

    private static func looksLikeSubtitleOnly(_ tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: ["subtitle", "subtitles", "caption", "captions", "字幕"]) && tokens.count <= 3
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return regex.matches(in: text, range: range).compactMap { match in
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard targetRange.location != NSNotFound else { return nil }
            return nsText.substring(with: targetRange)
        }
    }

    private static let noiseTokens: Set<String> = [
        "chs", "cht", "cn", "sc", "tc", "zh", "zhcn", "zhtw",
        "jp", "jpn", "ja", "en", "eng",
        "subtitle", "subtitles", "caption", "captions", "sub",
        "字幕", "中文", "简体", "繁体", "汉化", "翻译", "外挂"
    ]
}

private struct Fingerprint {
    let normalized: String
    let tokens: Set<String>
    let workIDs: Set<String>
    let trackNumbers: Set<String>
}
