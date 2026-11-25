/// The healthcheck lines that run but do not do what they look like.
enum FileChecks {
    static let operators: Set<String> = ["||", "&&", "|", ";", ">", ">>", "<", "&", "2>&1", "2>/dev/null",
                                         ">/dev/null"]
    static let shells: Set<String> = ["sh", "bash", "ash", "dash", "zsh"]

    static func lineProblems(_ node: ComposeNode, service: HealthService, variables: Variables,
                             lines: [String]) -> [FileFinding] {
        guard let entries = node.entries else { return [] }
        var found: [FileFinding] = []
        func report(_ problem: FileProblem, _ entry: ComposeEntry, _ detail: String) {
            found.append(FileFinding(problem: problem, service: service.name, line: entry.line, detail: detail,
                                     source: HealthcheckReader.line(entry.line, in: lines)))
        }
        if let test = entries.last(where: { $0.key == "test" }) {
            let words = test.value.text.map { [$0] } ?? test.value.items?.compactMap(\.text) ?? []
            for (problem, detail) in testProblems(words, isString: test.value.text != nil) {
                report(problem, test, detail)
            }
            for name in containerNames(words, service: service, variables: variables) {
                report(.containerVariable, test, "$" + name)
            }
            if let port = publishedPort(words.joined(separator: " "), ports: service.ports) {
                report(.publishedPortInTest, test, "\(port.published):\(port.target)")
            }
            if entries.last(where: { $0.key == "disable" })?.value.text.map(HealthcheckReader.isTrue) == true {
                report(.disableWithTest, test, "disable: true")
            }
        }
        if let retries = entries.last(where: { $0.key == "retries" }), retries.value.text == "0" {
            report(.retriesZero, retries, "0")
        }
        return found
    }

    /// Problems in the written `test:` words: a string, or a list starting with its type.
    static func testProblems(_ words: [String], isString: Bool) -> [(FileProblem, String)] {
        guard !isString, let type = words.first else { return [] }
        if type == "CMD-SHELL", words.count > 2 { return [(.scriptInPieces, words[1])] }
        guard type == "CMD" else { return [] }
        var problems: [(FileProblem, String)] = []
        if let item = words.dropFirst().first(where: { operators.contains($0.trimmed) }) {
            problems.append((.operatorInExecForm, item))
        }
        if !startsShell(Array(words.dropFirst())),
           let name = words.lazy.flatMap(Interpolation.escapedNames).first {
            problems.append((.variableInExecForm, "$$" + name))
        }
        return problems
    }

    /// `sh -c "script"` and the like: the shell expands what follows.
    static func startsShell(_ argv: [String]) -> Bool {
        guard argv.count >= 2 else { return false }
        return shells.contains { argv[0] == $0 || argv[0].hasSuffix("/" + $0) } && argv[1] == "-c"
    }

    /// `$NAME` written for compose to substitute that only the service's `environment:` sets.
    static func containerNames(_ words: [String], service: HealthService, variables: Variables) -> [String] {
        var names: [String] = []
        for word in words {
            let defaulted = Set(Interpolation.defaultedNames(in: word))
            for name in Interpolation.names(in: word) where !defaulted.contains(name) && !variables.knows(name)
                && service.environment.contains(name) && !names.contains(name) {
                names.append(name)
            }
        }
        return names
    }

    /// A `localhost:PORT` in the test where PORT is a published host port that maps to another container port.
    static func publishedPort(_ text: String, ports: [PortPair]) -> PortPair? {
        let targets = Set(ports.map(\.target))
        for host in ["localhost:", "127.0.0.1:", "0.0.0.0:"] {
            var rest = Substring(text)
            while let range = rest.range(of: host) {
                rest = rest[range.upperBound...]
                guard let port = Int(rest.prefix(while: \.isASCIIDigit)), !targets.contains(port) else { continue }
                if let pair = ports.first(where: { $0.published == port }) { return pair }
            }
        }
        return nil
    }
}
