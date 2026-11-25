/// Where each rule's topic starts in a clause.
extension RuleCues {
    static let markerWords = ["healthcheck", "health check", "healthchecks", "health checks", "health-check",
                              "the check", "the test command"]
    static let markerCodes: Set<String> = ["test", "test:", "HEALTHCHECK", "healthcheck", "healthcheck:", "CMD-SHELL"]
    static let fields: Set<String> = Set(HealthSetting.allCases.flatMap { [$0.rawValue, $0.rawValue + ":", $0.flag] })

    /// The clause names a healthcheck itself.
    static func marker(_ scan: Scan) -> String.Index? {
        [scan.anyPosition(of: markerWords), scan.code { markerCodes.contains($0) || isExecList($0) }]
            .compactMap { $0 }.min()
    }

    static func isExecList(_ code: String) -> Bool {
        var compact = code.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "\"")
        if compact.hasPrefix("test:") { compact.removeFirst(5) }
        return compact.hasPrefix("[\"CMD\"")
    }

    /// The exec form, unless the list starts a shell itself (`["CMD", "sh", "-c", "..."]`).
    static func execForm(_ scan: Scan) -> String.Index? {
        if scan.codes.contains(where: { isExecList($0.code) && startsShell($0.code) }) { return nil }
        if let code = scan.code(where: isExecList) { return code }
        guard marker(scan) != nil || scan.codes.contains(where: { $0.code == "CMD" }) else { return nil }
        return scan.anyPosition(of: ["exec form", "exec-form", "the cmd form", "cmd form", "array form", "list form",
                                     "json form", "json array form"])
    }

    static func startsShell(_ code: String) -> Bool {
        let compact = code.replacingOccurrences(of: " ", with: "")
        return ["\"sh\",\"-c\"", "\"bash\",\"-c\"", "\"/bin/sh\",\"-c\"", "\"/bin/bash\",\"-c\""]
            .contains { compact.contains($0) }
    }

    /// A string `test:`, `CMD-SHELL`, or the Dockerfile's shell form.
    static func stringForm(_ scan: Scan) -> String.Index? {
        let code = scan.code { code in
            if code == "CMD-SHELL" { return true }
            for prefix in ["HEALTHCHECK CMD ", "test: "] where code.hasPrefix(prefix) {
                return !code.dropFirst(prefix.count).trimmed.hasPrefix("[")
            }
            return false
        }
        if let code { return code }
        guard marker(scan) != nil || scan.showsHealthcheck else { return nil }
        return scan.anyPosition(of: ["a string", "string form", "shell form", "plain string", "the string",
                                     "test string", "healthcheck string"])
    }

    static func startPeriod(_ scan: Scan) -> String.Index? {
        guard scan.contains(["failure", "failures", "failed", "fails"]) else { return nil }
        return [scan.code { ["start_period", "start_period:", "--start-period"].contains($0) },
                scan.anyPosition(of: ["start period", "start_period"])].compactMap { $0 }.min()
    }

    static func instructions(_ scan: Scan) -> String.Index? {
        guard scan.contains(["instruction", "instructions", "line", "lines", "dockerfile"]) else { return nil }
        return [scan.code { $0 == "HEALTHCHECK" }, scan.anyPosition(of: ["healthcheck instruction"])]
            .compactMap { $0 }.min()
    }

    static func carriedOptions(_ scan: Scan) -> String.Index? {
        let several = scan.contains(["two", "several", "multiple", "earlier", "first", "previous", "second",
                                     "another"])
        let options = scan.code { $0.hasPrefix("--") && fields.contains($0) } != nil
            || scan.contains(["options", "flags"])
        guard several, options else { return nil }
        return [scan.code { $0 == "HEALTHCHECK" }, scan.anyPosition(of: ["healthcheck"])].compactMap { $0 }.min()
    }

    static func timeout(_ scan: Scan) -> String.Index? {
        guard marker(scan) != nil || scan.showsHealthcheck else { return nil }
        return [scan.code { ["timeout", "timeout:", "--timeout"].contains($0) },
                scan.anyPosition(of: ["times out", "timed out", "time out", "takes longer than", "runs longer than",
                                      "exceeds the timeout", "hits the timeout"])].compactMap { $0 }.min()
    }

    static let imageWords = ["image's", "the image", "from the image", "dockerfile", "base image"]

    /// Some healthcheck fields set in compose, the others left to the image.
    static func partialOverride(_ scan: Scan) -> String.Index? {
        let image = scan.code { $0 == "HEALTHCHECK" } != nil || scan.anyPosition(of: imageWords) != nil
        let namesTest = scan.codes.contains { $0.code == "test" || $0.code.hasPrefix("test:") }
        guard image, !namesTest else { return nil }
        return [scan.code { fields.contains($0) },
                scan.anyPosition(of: ["the fields you", "fields you leave out", "other fields", "the rest of the"])]
            .compactMap { $0 }.min()
    }

    static func disabling(_ scan: Scan) -> String.Index? {
        let image = scan.code { $0 == "HEALTHCHECK" } != nil
            || scan.anyPosition(of: ["image", "dockerfile", "base image", "inherited"]) != nil
        guard image, marker(scan) != nil else { return nil }
        let codes: Set<String> = ["disable: true", "disable", "disable:", "[\"NONE\"]", "test: [\"NONE\"]", "NONE",
                                  "HEALTHCHECK NONE"]
        return [scan.code { codes.contains($0) }, scan.anyPosition(of: ["compose"])].compactMap { $0 }.min()
    }

    static let expansions = ["expand", "expands", "expanded", "substitute", "substitutes", "substituted",
                             "interpolate", "interpolates", "interpolated", "resolve", "resolves", "resolved",
                             "replaced", "fill", "fills", "filled", "evaluated", "evaluates", "picked up",
                             "picks up", "read", "reads", "comes from", "come from", "taken from", "pulled from"]

    static func variable(_ scan: Scan, escaped: Bool) -> String.Index? {
        guard let token = scan.clause.variableToken, Clause.variableName(token).escaped == escaped,
              scan.contains(expansions), marker(scan) != nil || scan.showsHealthcheck else { return nil }
        return scan.code { $0 == token }
    }

    static func retriesZero(_ scan: Scan) -> String.Index? {
        [scan.code { $0.replacingOccurrences(of: " ", with: "") == "retries:0" },
         scan.anyPosition(of: ["zero retries", "retries of 0", "retries to 0", "retries at 0"])].compactMap { $0 }.min()
    }
}
