/// Reads what an answer says about healthchecks: general statements, stated defaults, and the healthcheck lines of
/// the answer's own files.
public struct HealthClaimReader: Sendable {
    public init() {}

    /// Sentences about other systems' health checks: there the words mean other things ("unhealthy is restarted"
    /// holds in Kubernetes and Swarm).
    static let elsewhere = ["kubernetes", "kubelet", "k8s", "liveness", "readiness", "startup probe", "swarm",
                            "autoheal", "ecs", "nomad", "systemd", "load balancer", "target group", "alb", "elb",
                            "consul", "podman", "health-on-failure", "docker service", "replicas"]
    static let otherKeys: Set<String> = ["command", "command:", "entrypoint", "entrypoint:", "CMD", "ENTRYPOINT"]

    public func claims(in text: String, scene: HealthScene) -> [HealthClaim] {
        guard scene.aboutDocker else { return [] }
        var claims = scene.answerProblems.map { HealthClaim(kind: .file($0), sentence: $0.source) }
        for block in AnswerBlocks.split(text) where block.kind == .prose {
            for sentence in Sentences.split(block.lines) where !Words.containsAny(sentence.folded, Self.elsewhere) {
                claims += self.claims(sentence: sentence, scene: scene)
            }
        }
        return claims
    }

    func claims(sentence: String, scene: HealthScene) -> [HealthClaim] {
        let sentenceMarker = RuleCues.marker(Scan(Clause(sentence))) != nil
        let form = scene.testForms.count == 1 ? scene.testForms.first : nil
        var claims: [HealthClaim] = []
        for raw in Sentences.clauses(sentence).flatMap(Self.afterInstruction) {
            let scan = Scan(Clause(raw), showsHealthcheck: scene.showsHealthcheck || sentenceMarker, formInView: form)
            // A clause about `command:` or `entrypoint:` belongs to the command kits unless it names a healthcheck.
            // A bare `CMD` means the healthcheck's form only when one is in view.
            let others = scene.showsHealthcheck ? Self.otherKeys.subtracting(["CMD"]) : Self.otherKeys
            if scan.codes.contains(where: { others.contains($0.code) }), RuleCues.marker(scan) == nil { continue }
            claims += rules(scan).map { HealthClaim(kind: .rule($0.rule, affirmed: $0.affirmed), sentence: sentence) }
            if sentenceMarker || scene.showsHealthcheck {
                claims += DefaultReader.values(scan).map {
                    HealthClaim(kind: .defaultValue($0.setting, stated: $0.value), sentence: sentence)
                }
            }
        }
        return claims
    }

    static let subjects = ["docker", "compose", "the engine", "it", "the container", "the healthcheck", "the check",
                           "your container"]

    /// "Add `restart: always` and Docker restarts it": the instruction, then the statement after it.
    static func afterInstruction(_ clause: String) -> [String] {
        guard Clause(clause).isInstruction else { return [clause] }
        for subject in subjects {
            if let range = clause.range(of: " and " + subject + " ", options: .caseInsensitive) {
                return [String(clause[..<range.lowerBound]), String(clause[range.lowerBound...].dropFirst(5))]
            }
        }
        return [clause]
    }

    struct Statement: Hashable {
        let rule: Rule
        let affirmed: Bool
    }

    /// The rules a clause states; two cues that contradict each other in one clause state nothing.
    func rules(_ scan: Scan) -> [Statement] {
        var found: [Statement] = []
        for cue in RuleCues.all {
            guard let topic = cue.topic(scan), cue.allowsInstruction || !scan.clause.isInstruction,
                  let phrase = scan.first(of: cue.phrases, from: cue.topicFirst ? topic : nil),
                  !scan.hypothetical(before: phrase) else { continue }
            let negated = scan.negated(before: phrase)
            guard scan.negations == (negated ? 1 : 0) else { continue }
            let (rule, affirmed) = cue.rule.canonical(affirmed: cue.affirms != negated)
            let statement = Statement(rule: rule, affirmed: affirmed)
            if !found.contains(statement) { found.append(statement) }
        }
        return found.filter { statement in
            !found.contains(Statement(rule: statement.rule, affirmed: !statement.affirmed))
        }
    }
}
