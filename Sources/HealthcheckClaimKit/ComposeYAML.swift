/// Reads the YAML a compose file is usually written in: block mappings and sequences, flow collections of scalars,
/// quoted and plain scalars, literal (`|`) and folded (`>`) block scalars read exactly, and comments. Anything else
/// (anchors, aliases, tags, `<<` merges, several documents, plain values continued on the next line, a folded block
/// with more-indented lines) is refused with a reason, so a file this reader does not follow leaves its healthchecks
/// unchecked instead of misread.
enum ComposeYAML {
    struct Unsupported: Error, Equatable {
        let reason: String
    }

    struct Line: Equatable {
        let number: Int
        let indent: Int
        let text: String
    }

    static func parse(_ source: String) throws(Unsupported) -> ComposeNode {
        let raw = source.components(separatedBy: "\n")
        var lines: [Line] = []
        for (offset, line) in raw.enumerated() {
            let content = stripComment(line)
            let indent = content.prefix { $0 == " " }.count
            let rest = content.dropFirst(indent)
            let text = rest.trimmed
            if text.isEmpty { continue }
            if rest.first == "\t" { throw Unsupported(reason: "tabs in the indentation (line \(offset + 1))") }
            if text == "---", lines.isEmpty { continue }
            if text == "---" || text == "..." || text.hasPrefix("%") {
                throw Unsupported(reason: "several YAML documents or a directive (line \(offset + 1))")
            }
            lines.append(Line(number: offset + 1, indent: indent, text: text))
        }
        guard let first = lines.first else { return .null }
        var parser = Parser(lines: lines, raw: raw)
        let node = try parser.block(indent: first.indent)
        if parser.index < lines.count {
            throw Unsupported(reason: "indentation this reader does not follow (line \(lines[parser.index].number))")
        }
        return node
    }

    /// The line without its comment: a `#` at the start or after a space, outside a quoted scalar.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character?
        var output = ""
        var characters = ArraySlice(line)
        while let character = characters.popFirst() {
            if let open = quote {
                if character == open, open == "'", characters.first == "'" {
                    output.append(character)
                    output.append(characters.removeFirst())
                    continue
                }
                if character == "\\", open == "\"", let escaped = characters.popFirst() {
                    output.append(character)
                    output.append(escaped)
                    continue
                }
                if character == open { quote = nil }
            } else if character == "#", previous == nil || previous?.isWhitespace == true {
                break
            } else if character == "\"" || character == "'", opensQuote(output) {
                quote = character
            }
            output.append(character)
            previous = character
        }
        return output
    }

    /// A quote opens a scalar only where one starts: at the line's start, after `key: `, `- `, `[`, `{` or `,`.
    static func opensQuote(_ before: String) -> Bool {
        let kept = before.trimmed
        guard let last = kept.last else { return true }
        if last == "[" || last == "," || last == "{" { return true }
        return (last == ":" || last == "-") && before.last?.isWhitespace == true
    }

    struct Parser {
        var lines: [Line]
        let raw: [String]
        var index = 0

        mutating func block(indent: Int) throws(Unsupported) -> ComposeNode {
            isItem(lines[index].text) ? try sequence(indent: indent) : try mapping(indent: indent)
        }

        func isItem(_ text: String) -> Bool {
            text == "-" || text.hasPrefix("- ")
        }

        mutating func sequence(indent: Int) throws(Unsupported) -> ComposeNode {
            var items: [ComposeNode] = []
            while index < lines.count, lines[index].indent == indent, isItem(lines[index].text) {
                let line = lines[index]
                let afterDash = line.text.dropFirst()
                let rest = afterDash.trimmed
                if rest.isEmpty {
                    index += 1
                    items.append(try nested(after: indent, sameIndentSequence: false))
                } else if isItem(rest) {
                    throw Unsupported(reason: "a sequence inside a sequence item (line \(line.number))")
                } else if ComposeYAML.key(rest) != nil {
                    // "- key: value": a mapping whose first key sits where the text after the dash starts.
                    let column = indent + 1 + afterDash.prefix { $0 == " " }.count
                    lines[index] = Line(number: line.number, indent: column, text: rest)
                    items.append(try mapping(indent: column))
                } else if let header = rest.first, header == "|" || header == ">" {
                    index += 1
                    items.append(try blockScalar(rest, line: line.number, deeperThan: indent))
                } else {
                    index += 1
                    items.append(try ComposeYAML.value(rest, line: line.number))
                    try noContinuation(deeperThan: indent)
                }
            }
            return .list(items)
        }

        mutating func mapping(indent: Int) throws(Unsupported) -> ComposeNode {
            var entries: [ComposeEntry] = []
            while index < lines.count, lines[index].indent == indent {
                let line = lines[index]
                guard !isItem(line.text), let (key, rest) = ComposeYAML.key(line.text) else {
                    throw Unsupported(reason: "a line that is not `key: value` (line \(line.number))")
                }
                if key == "<<" { throw Unsupported(reason: "a `<<` merge key (line \(line.number))") }
                index += 1
                let value: ComposeNode
                if rest.isEmpty {
                    value = try nested(after: indent, sameIndentSequence: true)
                } else if let header = rest.first, header == "|" || header == ">" {
                    value = try blockScalar(rest, line: line.number, deeperThan: indent)
                } else {
                    value = try ComposeYAML.value(rest, line: line.number)
                    try noContinuation(deeperThan: indent)
                }
                entries.append(ComposeEntry(key: key, value: value, line: line.number))
            }
            return .map(entries)
        }

        /// The block under a key or a bare dash. Under a key, a sequence may sit at the key's own indentation.
        mutating func nested(after indent: Int, sameIndentSequence: Bool) throws(Unsupported) -> ComposeNode {
            guard index < lines.count else { return .null }
            let next = lines[index]
            if next.indent > indent { return try block(indent: next.indent) }
            if sameIndentSequence, next.indent == indent, isItem(next.text) { return try sequence(indent: indent) }
            return .null
        }

        /// A `|` or `>` block, read from the file's own lines (comment-like lines and blank lines are text there):
        /// `|` keeps the line breaks, `>` folds lines into one with spaces (a blank line keeps one break); the final
        /// break is kept once, dropped (`-`) or kept with the blank lines after it (`+`).
        mutating func blockScalar(_ header: String, line: Int, deeperThan indent: Int) throws(Unsupported)
            -> ComposeNode {
            let indicators = header.dropFirst()
            guard indicators.count <= 1, indicators.allSatisfy({ $0 == "-" || $0 == "+" }) else {
                throw Unsupported(reason: "a block scalar header this reader does not follow (line \(line))")
            }
            var body = try blockLines(after: line, deeperThan: indent)
            var trailing = 0
            while body.last == "" {
                body.removeLast()
                trailing += 1
            }
            if header.hasPrefix(">"), body.contains(where: { $0.first == " " || $0.first == "\t" }) {
                throw Unsupported(reason: "a folded block with more-indented lines (line \(line))")
            }
            let content = header.hasPrefix("|") ? body.joined(separator: "\n") : ComposeYAML.fold(body)
            return .scalar(ComposeYAML.chomp(content, isEmpty: body.isEmpty, trailing: trailing,
                                             indicator: indicators.first))
        }

        /// The lines of a block scalar under the header line, without the block's indentation; blank lines are "".
        mutating func blockLines(after line: Int, deeperThan indent: Int) throws(Unsupported) -> [String] {
            var body: [String] = []
            var cursor = line
            var contentIndent: Int?
            while cursor < raw.count {
                let text = raw[cursor]
                if text.allSatisfy({ $0 == " " }) {
                    body.append("")
                    cursor += 1
                    continue
                }
                let spaces = text.prefix { $0 == " " }.count
                if spaces <= indent { break }
                let column = contentIndent ?? spaces
                contentIndent = column
                guard spaces >= column else {
                    throw Unsupported(reason: "a block scalar line indented less than its first line "
                                          + "(line \(cursor + 1))")
                }
                body.append(String(text.dropFirst(column)))
                cursor += 1
            }
            while index < lines.count, lines[index].number <= cursor { index += 1 }
            return body
        }

        func noContinuation(deeperThan indent: Int) throws(Unsupported) {
            if index < lines.count, lines[index].indent > indent {
                throw Unsupported(reason: "a value continued on the next line (line \(lines[index].number))")
            }
        }
    }

    /// The final line breaks of a block scalar: one (clip), none (`-`), or all of them (`+`).
    static func chomp(_ content: String, isEmpty: Bool, trailing: Int, indicator: Character?) -> String {
        if isEmpty { return indicator == "+" ? String(repeating: "\n", count: trailing) : "" }
        switch indicator {
        case "-": return content
        case "+": return content + "\n" + String(repeating: "\n", count: trailing)
        default: return content + "\n"
        }
    }

    /// Folded lines: joined with a space, except that each blank line between two lines keeps one line break.
    static func fold(_ lines: [String]) -> String {
        var output = ""
        var breaks = 0
        var started = false
        for line in lines {
            if line.isEmpty {
                breaks += 1
                continue
            }
            if started {
                output += breaks > 0 ? String(repeating: "\n", count: breaks) : " "
            } else {
                output += String(repeating: "\n", count: breaks)
            }
            output += line
            breaks = 0
            started = true
        }
        return output
    }
}
