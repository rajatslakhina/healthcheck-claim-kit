/// One thing an answer says, or shows in a compose file or Dockerfile, about how a healthcheck behaves.
public struct HealthClaim: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// A general statement, stated as so (`affirmed`) or as not so.
        case rule(Rule, affirmed: Bool)
        /// "`interval` defaults to 30s": a default value, in nanoseconds for timings.
        case defaultValue(HealthSetting, stated: Int64)
        /// A healthcheck line in the answer's own file.
        case file(FileFinding)
    }

    public let kind: Kind
    /// The sentence the claim was read from, or the file line it rests on.
    public let sentence: String

    public init(kind: Kind, sentence: String) {
        self.kind = kind
        self.sentence = sentence
    }

    /// What makes a later claim the same mistake: the line number of a file claim does not.
    var repeatKey: String {
        switch kind {
        case let .rule(rule, affirmed): "rule:\(rule.rawValue):\(affirmed)"
        case let .defaultValue(setting, stated): "default:\(setting.rawValue):\(stated)"
        case let .file(finding): "file:\(finding.problem.rawValue):\(finding.detail)"
        }
    }
}

/// What one claim came to.
public struct HealthFinding: Sendable, Hashable {
    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        /// Worth a second look: it may be meant, but it rarely does what it looks like.
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: HealthClaim
    public let severity: Severity
    /// What is so instead, for a flagged claim.
    public let correction: String?
    /// The same mistake was flagged earlier in the conversation.
    public internal(set) var isRepeated = false

    public init(claim: HealthClaim, severity: Severity, correction: String?) {
        self.claim = claim
        self.severity = severity
        self.correction = correction
    }
}

/// Everything one answer's healthcheck claims came to.
public struct HealthReport: Sendable, Hashable {
    public enum Verdict: String, Sendable, Hashable, CaseIterable {
        /// Nothing said about healthchecks that could be checked.
        case noClaims
        /// Every claim holds.
        case verified
        /// Nothing wrong, but something needs a second look.
        case caution
        /// At least one claim or file line is wrong.
        case wrong
    }

    public let findings: [HealthFinding]
    public let verdict: Verdict

    public init(findings: [HealthFinding]) {
        self.findings = findings
        verdict = switch findings.map(\.severity).max() {
        case nil: .noClaims
        case .holds?: .verified
        case .caution?: .caution
        case .wrong?: .wrong
        }
    }

    /// The findings that need a correction or a second look.
    public var flagged: [HealthFinding] {
        findings.filter { $0.severity >= .caution }
    }

    /// Flagged findings that were already flagged earlier in the conversation.
    public var repeatedCount: Int {
        flagged.filter(\.isRepeated).count
    }

    /// One sentence per flagged finding.
    public var corrections: [String] {
        flagged.compactMap(\.correction)
    }

    public var summary: String {
        let wrong = findings.filter { $0.severity == .wrong }.count
        let caution = findings.filter { $0.severity == .caution }.count
        return "\(verdict.rawValue): \(findings.count) claim(s), \(wrong) wrong, \(caution) caution"
    }
}
