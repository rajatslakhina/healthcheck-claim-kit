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
        guard scan.contains(cues),
              scan.negations == negatedCues.filter({ scan.position(of: $0) != nil }).count else { return [] }
        let settings = scan.codes.compactMap { code in setting(code.code).map { ($0, code.range) } }
        var stated: [Stated] = []
        for (index, (setting, range)) in settings.enumerated() {
            let end = index + 1 < settings.count ? settings[index + 1].1.lowerBound : scan.plain.endIndex
            let words = scan.plain[range.upperBound..<end].split { $0.isWhitespace || $0 == "," || $0 == ";" }
                .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            if let value = setting.isDuration ? duration(words) : count(words) {
                stated.append(Stated(setting: setting, value: value))
            }
        }
        return stated
    }

    static let unitWords: [String: Int64] = [
        "ms": 1_000_000, "millisecond": 1_000_000, "milliseconds": 1_000_000, "s": 1_000_000_000, "sec": 1_000_000_000,
        "secs": 1_000_000_000, "second": 1_000_000_000, "seconds": 1_000_000_000, "min": 60_000_000_000,
        "mins": 60_000_000_000, "minute": 60_000_000_000, "minutes": 60_000_000_000, "h": 3_600_000_000_000,
        "hour": 3_600_000_000_000, "hours": 3_600_000_000_000
    ]

    /// The first duration in the words: `30s`, `1m30s`, `30 seconds`, `0`.
    static func duration(_ words: [String]) -> Int64? {
        for (index, word) in words.enumerated() {
            if word.first?.isASCIIDigit == true, word.last?.isLetter == true, let value = try? GoDuration.parse(word) {
                return value
            }
            guard let number = Double(word) else { continue }
            if index + 1 < words.count, let unit = unitWords[words[index + 1]] {
                return Int64(number * Double(unit))
            }
            if number == 0 { return 0 }
        }
        return nil
    }

    static let numberWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// The first whole number in the words, as digits or a word.
    static func count(_ words: [String]) -> Int64? {
        for word in words {
            if let number = Int64(word) { return number }
            if let index = numberWords.firstIndex(of: word) { return Int64(index) }
        }
        return nil
    }
}
