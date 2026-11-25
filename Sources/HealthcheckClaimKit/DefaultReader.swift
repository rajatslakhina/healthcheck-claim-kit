import Foundation

/// Reads stated defaults: "`interval` defaults to 30s", "if you don't set `retries`, it gives up after 5 failures".
/// Only settings written as code count (`interval`, `start_period:`, `--retries`), so "health checks run every 30
/// seconds by default" about some other system is not read.
enum DefaultReader {
    struct Stated: Hashable {
        let setting: HealthSetting
        let value: Int64
    }

    static let cues = ["default", "defaults", "by default", "if you leave", "when omitted", "if omitted", "if unset",
                       "when unset", "left out", "if you don't set", "if you do not set", "when not set",
                       "if not set"]
    /// Cues that hold a negation of their own.
    static let negatedCues = ["don't set", "do not set", "not set"]

    static func setting(_ code: String) -> HealthSetting? {
        var name = code.trimmed
        if name.hasSuffix(":") { name.removeLast() }
        if name.hasPrefix("--") { name = String(name.dropFirst(2)).replacingOccurrences(of: "-", with: "_") }
        return HealthSetting(rawValue: name)
    }

    static func values(_ scan: Scan) -> [Stated] {
        guard !scan.clause.isInstruction, scan.contains(cues),
              scan.negations == negatedCues.filter({ scan.position(of: $0) != nil }).count else { return [] }
        let settings = scan.codes.compactMap { code in setting(code.code).map { ($0, code.range) } }
        var stated: [Stated] = []
        var previousCued = false
        for (index, (setting, range)) in settings.enumerated() {
            let start = index > 0 ? settings[index - 1].1.upperBound : scan.plain.startIndex
            let end = index + 1 < settings.count ? settings[index + 1].1.lowerBound : scan.plain.endIndex
            let segment = String(scan.plain[range.upperBound..<end])
            let lead = String(scan.plain[start..<range.lowerBound])
            // The cue sits by the setting ("the default `timeout`", "`interval` defaults to"), or the setting
            // continues a cued one ("... defaults to 30s and `retries` to 3").
            let cued = Words.containsAny(segment, cues) || Words.containsAny(lead, cues)
                || (previousCued && segment.trimmed.hasPrefix("to "))
            previousCued = cued
            let words = segment.split { $0.isWhitespace || $0 == "," || $0 == ";" }
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            let values = setting.isDuration ? durations(words) : counts(words)
            if cued, values.count == 1 { stated.append(Stated(setting: setting, value: values[0])) }
        }
        return stated
    }

    static let unitWords: [String: Int64] = [
        "ms": 1_000_000, "millisecond": 1_000_000, "milliseconds": 1_000_000, "s": 1_000_000_000, "sec": 1_000_000_000,
        "secs": 1_000_000_000, "second": 1_000_000_000, "seconds": 1_000_000_000, "min": 60_000_000_000,
        "mins": 60_000_000_000, "minute": 60_000_000_000, "minutes": 60_000_000_000, "h": 3_600_000_000_000,
        "hour": 3_600_000_000_000, "hours": 3_600_000_000_000
    ]

    /// The durations in the words: `30s`, `1m30s`, `30 seconds`, `0`.
    static func durations(_ words: [String]) -> [Int64] {
        var found: [Int64] = []
        for (index, word) in words.enumerated() {
            if word.first?.isASCIIDigit == true, word.last?.isLetter == true, let value = try? GoDuration.parse(word) {
                found.append(value)
                continue
            }
            guard let number = Double(word) else { continue }
            if index + 1 < words.count, let unit = unitWords[words[index + 1]] {
                found.append(Int64(number * Double(unit)))
            } else if number == 0 {
                found.append(0)
            }
        }
        return found
    }

    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// The whole numbers in the words, as digits or words.
    static func counts(_ words: [String]) -> [Int64] {
        words.compactMap { word in Int64(word) ?? numberWords.firstIndex(of: word).map(Int64.init) }
    }
}
