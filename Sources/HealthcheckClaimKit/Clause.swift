/// One clause of a sentence, ready for matching: its code spans, its words without code marks, and its prose with
/// the code masked.
struct Clause: Sendable, Hashable {
    let text: String
    /// Code marks removed, folded.
    let plain: String
    /// Code replaced by a bullet, folded.
    let prose: String
    let codes: [String]

    static let leadIns = ["note that", "remember that", "keep in mind that", "be aware that", "beware that", "also,",
                          "also", "so", "and", "but", "here,", "in short,", "in other words,", "because", "since",
                          "that's because", "this is because", "the reason is that", "that is,", "now,", "then,",
                          "otherwise,", "instead,", "in fact,", "actually,", "however,", "no,", "yes,", "right,",
                          "correct,", "exactly,", "indeed,"]

    init(_ raw: String) {
        var text = raw.trimmed
        var changed = true
        while changed {
            changed = false
            for leadIn in Self.leadIns where text.folded.hasPrefix(leadIn + " ") {
                text = String(text.dropFirst(leadIn.count)).trimmed
                changed = true
            }
        }
        self.text = text
        plain = Sentences.plain(text)
        prose = Sentences.prose(text)
        codes = Sentences.codeSpans(text)
    }

    static let imperatives: Set<String> = ["use", "wrap", "write", "put", "add", "set", "change", "replace", "try",
                                           "make", "remember", "avoid", "prefer", "keep", "move", "switch", "quote",
                                           "escape", "split", "run", "call", "pass", "define", "declare", "consider",
                                           "do", "don't", "never", "always", "rewrite", "check", "drop", "remove",
                                           "give", "list", "turn", "start", "override", "point", "fix"]

    /// The clause tells the reader to do something.
    var isInstruction: Bool {
        prose.split(whereSeparator: \.isWhitespace).prefix(1).contains { word in
            Self.imperatives.contains(word.trimmingCharacters(in: .punctuationCharacters))
        }
    }

    static let hypotheticals = ["would", "might", "could", "may", "expect", "expected", "expects", "think", "thought",
                                "seems", "looks like", "intended", "meant to", "want", "wanted", "suppose",
                                "assume", "imagine", "you'd", "should", "hoped", "myth", "misconception",
                                "mistakenly", "wrongly", "not true", "contrary to", "popular belief",
                                "supposed to", "as if", "pretend"]

    /// The clause describes what someone expects, not what happens.
    var isHypothetical: Bool {
        Words.containsAny(prose, Self.hypotheticals)
    }

    /// The first code span that is a variable: `$NAME`, `${NAME...}`, `$$NAME`, `$${NAME}`.
    var variableToken: String? {
        codes.first(where: Self.isVariable)
    }

    static func isVariable(_ code: String) -> Bool {
        var rest = Substring(code)
        guard rest.hasPrefix("$") else { return false }
        rest = rest.dropFirst()
        if rest.hasPrefix("$") { rest = rest.dropFirst() }
        if rest.hasPrefix("{") {
            return rest.hasSuffix("}") && Names.isName(String(rest.dropFirst().prefix(while: Names.isNameCharacter)))
        }
        return Names.isName(String(rest))
    }

    /// The variable's name and whether it is written `$$NAME`.
    static func variableName(_ token: String) -> (name: String, escaped: Bool) {
        let escaped = token.hasPrefix("$$")
        let body = token.drop { $0 == "$" || $0 == "{" }
        return (String(body.prefix(while: Names.isNameCharacter)), escaped)
    }
}
