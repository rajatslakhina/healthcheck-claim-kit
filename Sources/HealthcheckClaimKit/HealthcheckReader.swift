/// Reads a service's `healthcheck:` the way compose hands it to the engine: variables substituted, a string `test:`
/// made `["CMD-SHELL", string]`, `disable: true` made `["NONE"]`, timings read as Go durations. A setting compose
/// or the engine refuses becomes a problem; one this reader does not follow is left unset.
struct HealthcheckReader {
    let service: String
    let variables: Variables
    let lines: [String]
    var problems: [FileFinding] = []

    init(service: String, variables: Variables, lines: [String]) {
        self.service = service
        self.variables = variables
        self.lines = lines
    }

    mutating func read(_ node: ComposeNode) -> Healthcheck {
        var check = Healthcheck()
        guard let entries = node.entries else { return check }
        for entry in entries {
            switch entry.key {
            case "test":
                check.test = test(entry)
            case "retries":
                check.retries = retries(entry)
            default:
                if let setting = HealthSetting(rawValue: entry.key), setting.isDuration {
                    set(setting, duration(entry), on: &check)
                }
            }
        }
        if entries.last(where: { $0.key == "disable" })?.value.text.map(Self.isTrue) == true { check.test = ["NONE"] }
        return check
    }

    static func isTrue(_ text: String) -> Bool {
        ["true", "True", "TRUE"].contains(text)
    }

    func set(_ setting: HealthSetting, _ value: Int64, on check: inout Healthcheck) {
        switch setting {
        case .interval: check.interval = value
        case .timeout: check.timeout = value
        case .startPeriod: check.startPeriod = value
        default: check.startInterval = value
        }
    }

    func resolved(_ text: String) -> String? {
        try? Interpolation.resolve(text, variables).value
    }

    mutating func test(_ entry: ComposeEntry) -> [String]? {
        if let text = entry.value.text { return resolved(text).map { ["CMD-SHELL", $0] } }
        if entry.value == .null {
            report(.testWithoutValue, entry, detail: "test:")
            return nil
        }
        guard let items = entry.value.items, !items.isEmpty else { return nil }
        let texts = items.compactMap(\.text).compactMap(resolved)
        guard texts.count == items.count else { return nil }
        guard ["CMD", "CMD-SHELL", "NONE"].contains(texts[0]) else {
            report(.unknownTestType, entry, detail: texts[0])
            return nil
        }
        return texts
    }

    mutating func duration(_ entry: ComposeEntry) -> Int64 {
        guard let text = entry.value.text.flatMap(resolved) else { return 0 }
        // A plain number is a YAML number (refused: "must be a string"); a quoted one has no unit. Quoted "0" is fine.
        if Double(text) != nil, text != "0" {
            report(.durationNeedsUnit, entry, detail: "\(entry.key): \(text)")
            return 0
        }
        guard let value = try? GoDuration.parse(text) else {
            report(.durationRefused, entry, detail: "\(entry.key): \(text)")
            return 0
        }
        if value != 0, value < 1_000_000 {
            report(.durationTooShort, entry, detail: "\(entry.key): \(text)")
            return 0
        }
        return value
    }

    mutating func retries(_ entry: ComposeEntry) -> Int {
        guard let value = entry.value.text.flatMap(resolved).flatMap({ Int($0) }) else { return 0 }
        if value < 0 {
            report(.retriesNegative, entry, detail: "\(value)")
            return 0
        }
        return value
    }

    mutating func report(_ problem: FileProblem, _ entry: ComposeEntry, detail: String) {
        problems.append(FileFinding(problem: problem, service: service, line: entry.line, detail: detail,
                                    source: Self.line(entry.line, in: lines)))
    }

    static func line(_ number: Int, in lines: [String]) -> String {
        number >= 1 && number <= lines.count ? lines[number - 1].trimmed : ""
    }
}
