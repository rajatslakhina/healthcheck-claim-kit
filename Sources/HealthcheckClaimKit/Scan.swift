import Foundation

/// A clause ready for matching: its words folded with code marks removed, and where each code span sits in them.
/// A phrase found inside a code span does not count (`disable` in `disable: true`); one that starts in prose may run
/// into code (`wraps it in /bin/sh` over `` in `/bin/sh -c` ``).
struct Scan {
    let clause: Clause
    let plain: String
    let codes: [(code: String, range: Range<String.Index>)]
    /// The conversation shows a healthcheck, so a clause about "the string form" can mean one.
    let showsHealthcheck: Bool

    init(_ clause: Clause, showsHealthcheck: Bool = false) {
        self.clause = clause
        self.showsHealthcheck = showsHealthcheck
        var plain = ""
        var codes: [(String, Range<String.Index>)] = []
        var offsets: [(code: String, span: Range<Int>)] = []
        for piece in Sentences.pieces(clause.text) {
            let folded = piece.text.folded
            if piece.isCode { offsets.append((piece.text, plain.count..<plain.count + folded.count)) }
            plain += folded
        }
        for (code, span) in offsets {
            let start = plain.index(plain.startIndex, offsetBy: span.lowerBound)
            codes.append((code, start..<plain.index(start, offsetBy: span.count)))
        }
        self.plain = plain
        self.codes = codes
    }

    func inCode(_ index: String.Index) -> Bool {
        codes.contains { $0.range.contains(index) }
    }

    /// The first place a phrase occurs as words, starting in prose, at or after `from`.
    func position(of phrase: String, from: String.Index? = nil) -> String.Index? {
        var start = from ?? plain.startIndex
        while start < plain.endIndex, let range = plain.range(of: phrase, range: start..<plain.endIndex) {
            if Words.bounded(plain, range, phrase), !inCode(range.lowerBound) { return range.lowerBound }
            start = plain.index(after: range.lowerBound)
        }
        return nil
    }

    /// The first place a phrase occurs as words, code included: for topics such as "the `CMD` form".
    func anyPosition(of phrases: [String]) -> String.Index? {
        phrases.compactMap { Words.position(plain, $0) }.min()
    }

    func first(of phrases: [String], from: String.Index? = nil) -> String.Index? {
        phrases.compactMap { position(of: $0, from: from) }.min()
    }

    func contains(_ phrases: [String]) -> Bool {
        first(of: phrases) != nil
    }

    /// Where the first code span the test accepts starts.
    func code(where test: (String) -> Bool) -> String.Index? {
        codes.first { test($0.code.trimmed) }?.range.lowerBound
    }

    /// A negation just before `index`: "does not restart", "can't turn off", "doesn't always run on".
    func negated(before index: String.Index) -> Bool {
        var words = plain[..<index].split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        if let last = words.last, ["actually", "really", "always", "ever", "even", "necessarily", "just"]
            .contains(last) {
            words.removeLast()
        }
        guard let last = words.last else { return false }
        return ["not", "never", "cannot"].contains(last) || last.hasSuffix("n't")
    }

    /// How many negations the clause's prose holds.
    var negations: Int {
        Sentences.negationCount(clause.prose)
    }

    /// A word of expectation or supposition before `index`.
    func hypothetical(before index: String.Index) -> Bool {
        Words.containsAny(String(plain[..<index]), Clause.hypotheticals)
    }
}
