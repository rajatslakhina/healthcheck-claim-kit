/// Compose's variable substitution, done when it reads the file and before a healthcheck `test:` reaches the container:
/// `$VAR`, `${VAR}`, `${VAR:-default}`, `${VAR-default}`, `${VAR:?message}`, `${VAR?message}`, `${VAR:+other}`,
/// `${VAR+other}`, and `$$` for a literal `$`. The values come from the shell that runs `docker compose` and the
/// project's `.env`, never from the service's `environment:`. A `$` at the end or before `(` stays literal (probed);
/// any other `$` this reader does not follow leaves the value unfollowed.
enum Interpolation {
    enum Failure: Error, Hashable {
        /// `:?` or `?` stops `docker compose`.
        case required(name: String)
        /// Text this reader does not follow, such as `$1` or an unclosed `${`.
        case malformed
    }

    struct Result: Hashable {
        var value: String
        /// Names used that the conversation does not set; compose takes each from the shell, which is unseen.
        var unknown: Set<String>
    }

    static func resolve(_ text: String, _ variables: Variables) throws(Failure) -> Result {
        var resolver = Resolver(variables: variables)
        let value = try resolver.resolve(ArraySlice(text))
        return Result(value: value, unknown: resolver.unknown)
    }

    /// The names a text substitutes with a single `$` (`$NAME`, `${NAME...}`), in order; `$$NAME` is not one.
    static func names(in text: String) -> [String] {
        var names: [String] = []
        var rest = ArraySlice(text)
        while let character = rest.popFirst() {
            guard character == "$", let next = rest.first else { continue }
            if next == "$" {
                rest.removeFirst()
                continue
            }
            let body = next == "{" ? rest.dropFirst() : rest
            let name = String(body.prefix(while: Names.isNameCharacter))
            if Names.isName(name), !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// The names a text writes with a default (`${NAME:-x}`, `${NAME-x}`).
    static func defaultedNames(in text: String) -> [String] {
        names(in: text).filter { text.contains("${\($0):-") || text.contains("${\($0)-") }
    }

    /// The names a text writes as `$$NAME` or `$${NAME}`: passed to the container as `$NAME`.
    static func escapedNames(in text: String) -> [String] {
        var names: [String] = []
        var rest = ArraySlice(text)
        while let character = rest.popFirst() {
            guard character == "$", rest.first == "$" else { continue }
            rest.removeFirst()
            let body = rest.first == "{" ? rest.dropFirst() : rest
            let name = String(body.prefix(while: Names.isNameCharacter))
            if Names.isName(name), !names.contains(name) { names.append(name) }
        }
        return names
    }

    struct Resolver {
        let variables: Variables
        var unknown: Set<String> = []

        mutating func resolve(_ characters: ArraySlice<Character>) throws(Failure) -> String {
            var output = ""
            var rest = characters
            while let character = rest.popFirst() {
                guard character == "$" else {
                    output.append(character)
                    continue
                }
                guard let next = rest.first else {
                    output += "$"
                    continue
                }
                if next == "$" {
                    rest.removeFirst()
                    output += "$"
                } else if next == "(" {
                    output += "$"
                } else if next == "{" {
                    rest.removeFirst()
                    output += try braced(&rest)
                } else if Names.isNameCharacter(next), !next.isNumber {
                    let name = String(rest.prefix(while: Names.isNameCharacter))
                    rest.removeFirst(name.count)
                    output += lookup(name) ?? ""
                } else {
                    throw .malformed
                }
            }
            return output
        }

        mutating func lookup(_ name: String) -> String? {
            if !variables.knows(name) { unknown.insert(name) }
            return variables.value(name)
        }

        /// After `${`: the name, an operator and its word, up to the matching `}`.
        mutating func braced(_ rest: inout ArraySlice<Character>) throws(Failure) -> String {
            let name = String(rest.prefix(while: Names.isNameCharacter))
            guard Names.isName(name) else { throw .malformed }
            rest.removeFirst(name.count)
            var operation = ""
            while let character = rest.first, ":-?+".contains(character), operation.count < 2 {
                operation.append(rest.removeFirst())
            }
            var depth = 0
            var word: [Character] = []
            while true {
                guard let character = rest.popFirst() else { throw .malformed }
                if character == "}", depth == 0 { break }
                if character == "{", word.last == "$" { depth += 1 }
                if character == "}" { depth -= 1 }
                word.append(character)
            }
            return try apply(operation, name: name, word: ArraySlice(word))
        }

        mutating func apply(_ operation: String, name: String, word: ArraySlice<Character>) throws(Failure) -> String {
            let value = lookup(name)
            let isEmpty = value?.isEmpty ?? true
            switch operation {
            case "" where word.isEmpty:
                return value ?? ""
            case ":-":
                if let value, !isEmpty { return value }
                return try resolve(word)
            case "-":
                if let value { return value }
                return try resolve(word)
            case ":?", "?":
                return try required(operation, name: name, value: value)
            case ":+":
                return isEmpty ? "" : try resolve(word)
            case "+":
                return value == nil ? "" : try resolve(word)
            default:
                throw .malformed
            }
        }

        /// `${NAME:?message}` and `${NAME?message}`.
        func required(_ operation: String, name: String, value: String?) throws(Failure) -> String {
            // A name the conversation never sets comes from the unseen shell: unknown, not an error.
            guard variables.knows(name) else { return "" }
            guard let value, !(value.isEmpty && operation == ":?") else { throw .required(name: name) }
            return value
        }
    }
}

/// The variables compose substitutes into a compose file: the shell's environment, then the `.env` file next to it.
/// The shell wins. A name the conversation never sets is unknown: compose takes it from a shell nobody showed.
public struct Variables: Sendable, Hashable {
    /// Exported in the shell that runs `docker compose`.
    public var shell: [String: String]
    /// Set in the project's `.env` file.
    public var dotEnv: [String: String]
    /// Said to be unset.
    public var unset: Set<String>

    public init(shell: [String: String] = [:], dotEnv: [String: String] = [:], unset: Set<String> = []) {
        self.shell = shell
        self.dotEnv = dotEnv
        self.unset = unset
    }

    func knows(_ name: String) -> Bool {
        unset.contains(name) || shell[name] != nil || dotEnv[name] != nil
    }

    func value(_ name: String) -> String? {
        if unset.contains(name) { return nil }
        return shell[name] ?? dotEnv[name]
    }
}

/// Reads a `.env` file the way compose does for the plain cases: `#` lines and a ` #` after an unquoted value are
/// comments, `export ` is dropped, spaces around an unquoted value go, quotes around a value go. A value with a `$`
/// in it is left out (compose would substitute inside it), so the name stays unknown.
enum EnvFile {
    static func parse(_ lines: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for raw in lines {
            var line = raw.trimmed
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmed }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<equals]).trimmed
            guard Names.isName(name), let value = value(String(line[line.index(after: equals)...]).trimmed) else {
                continue
            }
            values[name] = value
        }
        return values
    }

    /// The value, or `nil` when this reader does not follow it.
    static func value(_ text: String) -> String? {
        if let quote = text.first, quote == "'" || quote == "\"" {
            guard text.count >= 2, text.last == quote else { return nil }
            let inside = String(text.dropFirst().dropLast())
            return quote == "\"" && inside.contains("$") ? nil : inside
        }
        let kept = text.range(of: " #").map { String(text[..<$0.lowerBound]) } ?? text
        return kept.contains("$") ? nil : kept.trimmed
    }

    /// Whether a code block looks like a `.env` file: every line a comment or `NAME=value`.
    static func looksLikeEnvFile(_ lines: [String]) -> Bool {
        let kept = lines.map(\.trimmed).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return !kept.isEmpty && kept.allSatisfy { line in
            guard let equals = line.firstIndex(of: "=") else { return false }
            return Names.isName(String(line[..<equals]))
        }
    }
}

enum Names {
    static func isName(_ text: String) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy(isNameCharacter)
    }

    static func isNameCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }
}
