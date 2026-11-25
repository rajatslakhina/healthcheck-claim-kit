/// Splits prose into sentences, sentences into clauses, and clauses into prose and inline code.
enum Sentences {
    static func split(_ lines: [String]) -> [String] {
        var sentences: [String] = []
        for line in lines {
            var current = ""
            let characters = Array(line)
            for (index, character) in characters.enumerated() {
                current.append(character)
                // A stop ends a sentence only before a space or the end of the line: `app.js` stays whole.
                let ends = index + 1 == characters.count || characters[index + 1].isWhitespace
                let abbreviation = ["vs.", "e.g.", "i.e.", "etc."].contains { current.lowercased().hasSuffix($0) }
                if ".!?".contains(character), ends, !abbreviation, current.filter({ $0 == "`" }).count % 2 == 0 {
                    sentences.append(current)
                    current = ""
                }
            }
            sentences.append(current)
        }
        return sentences.map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The sentence cut at its backticks: even pieces are prose, odd pieces are inline code.
    static func pieces(_ sentence: String) -> [(text: String, isCode: Bool)] {
        sentence.components(separatedBy: "`").enumerated().map { ($0.element, $0.offset % 2 == 1) }
    }

    /// The inline code spans of a sentence, in order.
    static func codeSpans(_ sentence: String) -> [String] {
        pieces(sentence).filter(\.isCode).map(\.text)
    }

    /// Where a sentence turns to another point, outside inline code: a contrast ("`command` is split, while a
    /// healthcheck string runs in a shell") reads as two claims.
    static let joints = ["; ", ", but ", ", while ", ", whereas ", " but ", " whereas ", ", so ", ", since ",
                         " because ", ", which ", " - ", " \u{2014} ", ", and "]

    static func clauses(_ sentence: String) -> [String] {
        var clauses: [String] = []
        var current = ""
        for piece in pieces(sentence) {
            if piece.isCode {
                current += "`" + piece.text + "`"
                continue
            }
            var parts = [piece.text]
            for joint in joints {
                parts = parts.flatMap { $0.components(separatedBy: joint) }
            }
            current += parts[0]
            for part in parts.dropFirst() {
                clauses.append(current)
                current = part
            }
        }
        clauses.append(current)
        return clauses.map(\.trimmed).filter { !$0.isEmpty }
    }

    /// The clause without inline-code marks, folded.
    static func plain(_ clause: String) -> String {
        clause.replacingOccurrences(of: "`", with: "").folded
    }

    /// The prose of a clause (inline code replaced by a marker), folded.
    static func prose(_ clause: String) -> String {
        pieces(clause).map { $0.isCode ? " \u{2022} " : $0.text }.joined().folded
    }

    static func negationCount(_ prose: String) -> Int {
        var count = 0
        for word in ["not", "never", "no longer", "neither", "nor", "cannot", "nothing", "none"]
            where Words.contains(prose, word) {
            count += 1
        }
        count += prose.components(separatedBy: "n't").count - 1
        return count
    }
}
