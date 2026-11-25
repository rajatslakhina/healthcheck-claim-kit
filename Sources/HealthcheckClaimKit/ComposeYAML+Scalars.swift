/// Keys, scalars and flow collections: the parts of the reader that work on one line.
extension ComposeYAML {
    /// The key and the rest of a `key: value` line, or `nil` when the text is a plain value.
    static func key(_ text: String) -> (String, String)? {
        if let open = text.first, open == "\"" || open == "'" {
            guard let (key, end) = quoted(text), text[end...].hasPrefix(":") else { return nil }
            let rest = text[text.index(after: end)...]
            guard rest.isEmpty || rest.first == " " else { return nil }
            return (key, rest.trimmed)
        }
        guard let first = text.first, !"[{&*!|>%@`".contains(first) else { return nil }
        if text.hasSuffix(":"), !text.dropLast().contains(": ") { return (String(text.dropLast()).trimmed, "") }
        guard let colon = text.range(of: ": ") else { return nil }
        return (String(text[..<colon.lowerBound]).trimmed, String(text[colon.upperBound...]).trimmed)
    }

    /// A quoted scalar at the start of the text, and the index just after its closing quote; `nil` when it does not
    /// close or holds an escape this reader does not follow.
    static func quoted(_ text: String) -> (String, String.Index)? {
        guard let open = text.first else { return nil }
        var value = ""
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == open {
                guard open == "'", next < text.endIndex, text[next] == "'" else { return (value, next) }
                value.append("'")
                index = text.index(after: next)
                continue
            }
            if character == "\\", open == "\"" {
                guard next < text.endIndex, let escaped = escape(text[next]) else { return nil }
                value.append(escaped)
                index = text.index(after: next)
                continue
            }
            value.append(character)
            index = next
        }
        return nil
    }

    /// A double-quoted scalar's escape: the ones compose files use; any other (`\x41`, `é`) is refused.
    static func escape(_ character: Character) -> Character? {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        case "\\", "\"", "/", " ": character
        default: nil
        }
    }

    /// A value written after `key: ` or `- `.
    static func value(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        let unsupported: [(Character, String)] = [("&", "an anchor"), ("*", "an alias"), ("!", "a tag"),
                                                  ("@", "a reserved character"), ("`", "a reserved character"),
                                                  ("%", "a directive character")]
        if let first = text.first, let (_, what) = unsupported.first(where: { $0.0 == first }) {
            throw Unsupported(reason: "\(what) (line \(line))")
        }
        if text.hasPrefix("[") { return try flow(text, line: line) }
        if text.hasPrefix("{") { return try flowMap(text, line: line) }
        if text.first == "\"" || text.first == "'" {
            guard let (value, end) = quoted(text), end == text.endIndex else {
                throw Unsupported(reason: "a quoted value this reader does not follow (line \(line))")
            }
            return .scalar(value)
        }
        if ["~", "null", "Null", "NULL"].contains(text) { return .null }
        if text.contains(": ") { throw Unsupported(reason: "a mapping inside a plain value (line \(line))") }
        return .scalar(text)
    }

    /// `{}` or `{a: 1, b: "x"}`: a flow mapping of scalars on one line.
    static func flowMap(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        guard text.hasSuffix("}"), text.count >= 2 else {
            throw Unsupported(reason: "a flow mapping over several lines (line \(line))")
        }
        var entries: [ComposeEntry] = []
        for item in try items(text.dropFirst().dropLast(), line: line) where !item.isEmpty {
            guard let (key, rest) = ComposeYAML.key(item) else {
                throw Unsupported(reason: "a flow mapping entry this reader does not follow (line \(line))")
            }
            entries.append(ComposeEntry(key: key, value: rest.isEmpty ? .null : try value(rest, line: line),
                                        line: line))
        }
        return .map(entries)
    }

    /// `["npm", "run", 'dev']`: a flow sequence of scalars on one line.
    static func flow(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        guard text.hasSuffix("]"), text.count >= 2 else {
            throw Unsupported(reason: "a flow sequence over several lines (line \(line))")
        }
        let trimmed = try items(text.dropFirst().dropLast(), line: line)
        if trimmed == [""] { return .list([]) }
        var nodes: [ComposeNode] = []
        for item in trimmed where !item.isEmpty {
            nodes.append(try value(item, line: line))
        }
        return .list(nodes)
    }

    /// The comma-separated items of a flow collection's inside, trimmed; commas inside quotes stay.
    static func items(_ inside: Substring, line: Int) throws(Unsupported) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false
        for character in inside {
            if let open = quote {
                if escaping {
                    escaping = false
                } else if character == "\\", open == "\"" {
                    escaping = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(current)
                current = ""
                continue
            } else if "[]{}".contains(character) {
                throw Unsupported(reason: "a nested flow collection (line \(line))")
            }
            current.append(character)
        }
        items.append(current)
        return items.map(\.trimmed)
    }
}
