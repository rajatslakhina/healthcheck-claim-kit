import Foundation

/// The healthcheck an image built from a Dockerfile carries.
public enum ImageHealth: Sendable, Hashable {
    /// Known: `nil` when the image has none.
    case known(Healthcheck?)
    /// The image starts from a base the conversation does not show, which may define one.
    case unknown
}

/// Reads a Dockerfile's `HEALTHCHECK` instructions: the last one in a stage replaces every earlier one, options
/// included; a stage built `FROM` another stage starts with that stage's; `FROM scratch` starts with none; any
/// other base is unseen. The shell form stays one string (`["CMD-SHELL", text]`), the JSON form is exec.
struct DockerfileHealth: Sendable, Hashable {
    struct Line: Hashable {
        let number: Int
        let text: String
    }

    var image: ImageHealth = .unknown
    var problems: [FileFinding] = []
    /// The Dockerfile writes at least one `HEALTHCHECK`.
    var hasHealthcheck = false

    static func read(_ text: String) -> DockerfileHealth {
        var result = DockerfileHealth()
        let lines = logicalLines(text)
        if lines.contains(where: { $0.text.folded.hasPrefix("# escape=") }) { return result }
        var stages: [String: ImageHealth] = [:]
        var current: String?
        for line in lines where !line.text.hasPrefix("#") {
            let keyword = line.text.prefix { !$0.isWhitespace }.uppercased()
            let arguments = String(line.text.dropFirst(keyword.count)).trimmed
            if keyword == "FROM" {
                (result.image, current) = start(arguments, stages: stages)
            } else if keyword == "HEALTHCHECK" {
                result.hasHealthcheck = true
                result.image = instruction(arguments).map(ImageHealth.known) ?? .unknown
                result.problems += problems(arguments, line: line)
            }
            if let current { stages[current] = result.image }
        }
        return result
    }

    /// Lines with `\` continuations joined, comments and blank lines dropped.
    static func logicalLines(_ text: String) -> [Line] {
        var result: [Line] = []
        var pending = ""
        var start = 0
        for (offset, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.trimmed
            if pending.isEmpty {
                if line.isEmpty { continue }
                start = offset + 1
            } else if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasSuffix("\\") {
                pending += String(line.dropLast()) + " "
                continue
            }
            result.append(Line(number: start, text: pending + line))
            pending = ""
        }
        if !pending.isEmpty { result.append(Line(number: start, text: pending.trimmed)) }
        return result
    }

    /// The healthcheck a stage starts with, and the stage's name.
    static func start(_ arguments: String, stages: [String: ImageHealth]) -> (ImageHealth, String?) {
        let words = arguments.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.hasPrefix("--") }
        guard let base = words.first?.lowercased() else { return (.unknown, nil) }
        let image: ImageHealth = base == "scratch" ? .known(nil) : stages[base] ?? .unknown
        let name = words.count >= 3 && words[1].lowercased() == "as" ? words[2].lowercased() : nil
        return (image, name)
    }

    /// One `HEALTHCHECK` instruction: `nil` when an option is one this reader does not follow.
    static func instruction(_ arguments: String) -> Healthcheck? {
        var check = Healthcheck()
        var rest = Substring(arguments)
        while rest.hasPrefix("--") {
            let option = rest.prefix { !$0.isWhitespace }
            rest = rest.dropFirst(option.count).drop(while: \.isWhitespace)
            guard set(String(option), on: &check) else { return nil }
        }
        let keyword = rest.prefix { !$0.isWhitespace }.uppercased()
        let command = String(rest.dropFirst(keyword.count)).trimmed
        switch keyword {
        case "NONE": return Healthcheck(test: ["NONE"])
        case "CMD" where !command.isEmpty:
            check.test = execForm(command).map { ["CMD"] + $0 } ?? ["CMD-SHELL", command]
            return check
        default: return nil
        }
    }

    /// `--interval=10s` and the like.
    static func set(_ option: String, on check: inout Healthcheck) -> Bool {
        let parts = option.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2, let setting = HealthSetting.allCases.first(where: { $0.flag == "--" + parts[0] })
        else { return false }
        if setting == .retries {
            guard let retries = Int(parts[1]), retries >= 0 else { return false }
            check.retries = retries
            return true
        }
        guard let value = try? GoDuration.parse(parts[1]) else { return false }
        switch setting {
        case .interval: check.interval = value
        case .timeout: check.timeout = value
        case .startPeriod: check.startPeriod = value
        default: check.startInterval = value
        }
        return true
    }

    /// The JSON array form's strings, or `nil` for the shell form.
    static func execForm(_ text: String) -> [String]? {
        guard text.hasPrefix("[") else { return nil }
        return try? JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    /// Exec-form items that a shell would have read: operators, and variables nothing expands.
    static func problems(_ arguments: String, line: Line) -> [FileFinding] {
        guard let range = arguments.range(of: "CMD", options: .caseInsensitive),
              let argv = execForm(String(arguments[range.upperBound...]).trimmed) else { return [] }
        var found: [FileFinding] = []
        if let item = argv.first(where: { FileChecks.operators.contains($0.trimmed) }) {
            found.append(FileFinding(problem: .operatorInExecForm, service: "", line: line.number, detail: item,
                                     source: line.text))
        }
        if !FileChecks.startsShell(argv), let name = argv.lazy.flatMap(Interpolation.names).first {
            found.append(FileFinding(problem: .variableInExecForm, service: "", line: line.number, detail: "$" + name,
                                     source: line.text))
        }
        return found
    }
}
