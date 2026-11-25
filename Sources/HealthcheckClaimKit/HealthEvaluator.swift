/// Judges claims: rules and defaults against the engine's behaviour, file lines by what compose and the engine do
/// with them.
struct HealthEvaluator {
    func judge(_ claim: HealthClaim) -> HealthFinding {
        switch claim.kind {
        case let .rule(rule, affirmed):
            if affirmed == rule.holds { return HealthFinding(claim: claim, severity: .holds, correction: nil) }
            return HealthFinding(claim: claim, severity: .wrong, correction: Wording.rule(rule))
        case let .defaultValue(setting, stated):
            if stated == setting.defaultValue { return HealthFinding(claim: claim, severity: .holds, correction: nil) }
            return HealthFinding(claim: claim, severity: .wrong, correction: Wording.defaultValue(setting, stated))
        case let .file(finding):
            return HealthFinding(claim: claim, severity: finding.problem.isWrong ? .wrong : .caution,
                          correction: Wording.file(finding))
        }
    }
}

/// Reads an answer's claims about healthchecks and judges each against Docker's behaviour and the files the
/// conversation shows.
public struct HealthClaimChecker: Sendable {
    public let reader: HealthClaimReader

    public init() {
        reader = HealthClaimReader()
    }

    /// What the answer and its context (the question, earlier turns) show.
    public func scene(for text: String, context: String = "") -> HealthScene {
        SceneReader.read(answer: text, context: context, earlier: nil)
    }

    public func claims(in text: String, context: String = "") -> [HealthClaim] {
        reader.claims(in: text, scene: scene(for: text, context: context))
    }

    public func judge(_ claim: HealthClaim) -> HealthFinding {
        HealthEvaluator().judge(claim)
    }

    public func check(_ text: String, context: String = "") -> HealthReport {
        check(text, context: context, earlier: nil).report
    }

    func check(_ text: String, context: String, earlier: HealthScene?) -> (report: HealthReport, scene: HealthScene) {
        let scene = SceneReader.read(answer: text, context: context, earlier: earlier)
        let findings = reader.claims(in: text, scene: scene).map(HealthEvaluator().judge)
        return (HealthReport(findings: findings), scene)
    }
}

/// Checks the answers of one conversation in turn: a compose file, Dockerfile or `.env` shown in an earlier answer
/// still counts for a later one, and a mistake stated again after it was flagged is marked as repeated.
public actor HealthLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: HealthClaimChecker
    public private(set) var statistics = Statistics()
    private var scene: HealthScene?
    private var flaggedBefore: Set<String> = []

    public init(checker: HealthClaimChecker = HealthClaimChecker()) {
        self.checker = checker
    }

    public func review(_ text: String, context: String = "") -> HealthReport {
        let (report, scene) = checker.check(text, context: context, earlier: scene)
        self.scene = scene
        let findings = report.findings.map { finding in
            var marked = finding
            if finding.severity >= .caution, flaggedBefore.contains(finding.claim.repeatKey) {
                marked.isRepeated = true
            }
            return marked
        }
        let marked = HealthReport(findings: findings)
        flaggedBefore.formUnion(marked.flagged.map(\.claim.repeatKey))
        statistics.reviews += 1
        statistics.claims += marked.findings.count
        statistics.flagged += marked.flagged.count
        statistics.repeated += marked.repeatedCount
        return marked
    }

    /// Starts a new conversation.
    public func forget() {
        scene = nil
        flaggedBefore = []
    }
}
