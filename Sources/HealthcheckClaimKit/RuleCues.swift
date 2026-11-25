/// The words that state each rule. A clause states a rule when its topic is there, one of the cue's phrases is
/// there (after the topic, unless the cue says the order is free), and the clause holds no other negation than one
/// just before the phrase, which turns the statement round.
struct RuleCue: Sendable {
    let rule: Rule
    /// Whether the phrases say the rule is so (`true`) or not so (`false`).
    let affirms: Bool
    /// Where the topic starts, or `nil` when the clause is not about it.
    let topic: @Sendable (Scan) -> String.Index?
    let phrases: [String]
    var topicFirst = true
    var allowsInstruction = false
    /// Words anywhere in the clause that make it state nothing for this cue.
    var excludes: [String] = []
}

enum RuleCues {
    static let shellPhrases = [
        "through a shell", "in a shell", "via a shell", "by a shell", "with a shell", "through /bin/sh",
        "via /bin/sh", "in /bin/sh", "through sh -c", "via sh -c", "in sh -c", "wrapped in /bin/sh",
        "wrapped in sh -c", "wraps it in /bin/sh", "wraps it in sh -c", "wraps it in a shell", "a shell runs it",
        "the shell parses", "the shell interprets", "interpreted by a shell", "interpreted by the shell",
        "parsed by a shell", "parsed by the shell", "run by a shell", "run by the shell", "executed by a shell",
        "executed by the shell", "executed in a shell", "shell features work", "is the shell form",
        "uses the shell form", "is shell form", "uses a shell",
        "uses the shell", "goes through a shell", "goes through the shell", "handled by a shell",
        "handled by the shell", "a shell handles"
    ]
    static let noShellPhrases = [
        "without a shell", "with no shell", "bypasses the shell", "skips the shell", "execs the program",
        "runs the program itself", "runs the program directly", "runs it directly", "execs it directly"
    ]
    static let hostPhrases = [
        "runs on the host", "run on the host", "is run on the host", "executes on the host", "is executed on the host",
        "runs from the host", "run from the host", "runs on your machine", "run on your machine",
        "runs on the host machine", "runs on your host", "run on your host"
    ]
    static let containerPhrases = [
        "runs inside the container", "run inside the container", "runs in the container", "run in the container",
        "is run inside the container", "is run in the container", "executes inside the container",
        "executes in the container", "is executed inside the container", "runs within the container",
        "runs it inside the container", "runs it in the container"
    ]
    static let keepPhrases = [
        "keeps the image's", "keep the image's", "come from the image", "comes from the image", "still come from",
        "still comes from", "inherited from the image", "inherits", "inherit", "are kept", "is kept",
        "still applies", "still apply", "fall back to the image's", "falls back to the image's",
        "keeps the dockerfile's", "come from the dockerfile", "comes from the dockerfile"
    ]
    /// The dropped thing must be the command, the test or the rest: a value compose sets does replace the image's.
    static let dropPhrases = [
        "command is dropped", "command is lost", "command is ignored", "command is discarded", "test is dropped",
        "test is lost", "test is ignored", "the rest is dropped", "the rest is lost", "everything else is dropped",
        "drops the image's command", "drops the image's test", "drops the image's healthcheck",
        "replaces the whole healthcheck", "replaces the entire healthcheck", "discards the image's healthcheck",
        "the image's healthcheck is dropped", "the image's healthcheck is ignored"
    ]
    static let lastPhrases = [
        "only the last", "the last one wins", "last one wins", "the last one takes effect", "the last one counts",
        "last one counts", "the last one is used", "the last one applies", "overrides the earlier",
        "override the earlier", "replaces the earlier", "replace the earlier", "only one takes effect"
    ]
    static let everyPhrases = [
        "runs every healthcheck", "run every healthcheck", "all of them run", "both run", "one after another",
        "each one runs", "they all run", "run in sequence", "runs them in order", "run them in order"
    ]
    static let carryPhrases = [
        "carry over", "carries over", "carried over", "still apply", "still applies", "are kept", "is kept",
        "are inherited", "is inherited", "keeps the first", "keep the first", "with the --interval from the first",
        "with the --timeout from the first", "with the --retries from the first", "with the options from the first"
    ]
    static let stopPhrases = [
        "kills the container", "kill the container", "stops the container", "stop the container",
        "restarts the container", "restart the container", "the container is killed", "the container is stopped",
        "the container is restarted", "the container gets killed", "shuts down the container",
        "takes the container down"
    ]
    static let failurePhrases = [
        "counts as a failure", "count as a failure", "counts as a failed", "is a failure", "is treated as a failure",
        "treated as a failure", "counted as a failure", "counts as one failure", "is a failed check",
        "marked as failed", "counts as failed"
    ]
    static let fromContainerPhrases = [
        "in the container", "inside the container", "at runtime", "at run time", "when the check runs",
        "when the healthcheck runs", "by the container", "from the container", "container's environment",
        "container's shell", "from environment", "from the environment section", "from the environment block",
        "the environment block", "the environment section", "the service's environment", "from the service's"
    ]
    static let fromShellPhrases = [
        "from your shell", "from the shell", "from the host", "on the host", "from .env", "from the .env",
        "from a .env", "in your shell", "when compose reads", "when it reads the file", "when compose parses",
        "when compose loads", "at parse time", "before the container starts", "when docker compose reads",
        "when the file is read", "when the file is parsed", "compose substitutes", "compose replaces",
        "compose interpolates"
    ]
    static let failFastPhrases = [
        "first failure", "first failed check", "first failed", "immediately", "right away", "never retries",
        "no retries", "disables retries", "disable retries", "without retrying", "after one failure",
        "a single failure", "one failed check", "on the first"
    ]
    static let unsetPhrases = [
        "the default", "means 3", "same as 3", "falls back to 3", "default of 3", "same as leaving it out",
        "treated as 3", "same as not setting it", "the image's value"
    ]

    static let all: [RuleCue] = shellCues + behaviourCues + overrideCues + variableCues + retriesCues

    /// Words that make a shell statement a requirement or a comparison, not a statement of what happens.
    static let shellExcludes = ["need", "needs", "must", "has to", "have to", "require", "requires", "than",
                                "unlike"]

    static let shellCues: [RuleCue] = [
        RuleCue(rule: .execFormUsesShell, affirms: true, topic: execForm, phrases: shellPhrases,
                excludes: shellExcludes),
        RuleCue(rule: .execFormUsesShell, affirms: false, topic: execForm, phrases: noShellPhrases,
                excludes: shellExcludes),
        RuleCue(rule: .stringFormUsesShell, affirms: true, topic: stringForm, phrases: shellPhrases,
                excludes: shellExcludes),
        RuleCue(rule: .stringFormUsesShell, affirms: false, topic: stringForm, phrases: noShellPhrases,
                excludes: shellExcludes)
    ]

    static let behaviourCues: [RuleCue] = [
        RuleCue(rule: .unhealthyRestarts, affirms: true, topic: { $0.position(of: "unhealthy") },
                phrases: ["restarts", "is restarted", "gets restarted", "are restarted", "get restarted",
                          "will restart", "recreates", "is recreated", "doesn't restart", "does not restart",
                          "won't restart", "will not restart", "never restarts"], topicFirst: false),
        RuleCue(rule: .runsOnHost, affirms: true, topic: marker, phrases: hostPhrases),
        RuleCue(rule: .runsInContainer, affirms: true, topic: marker, phrases: containerPhrases),
        RuleCue(rule: .startPeriodFailuresCount, affirms: true, topic: startPeriod,
                phrases: ["count toward", "counts toward", "count towards", "counts towards", "count against",
                          "counts against", "are counted", "is counted", "counted", "count as failures",
                          "counted as failures",
                          "count for retries", "count in retries"], topicFirst: false,
                excludes: ["after", "once", "later", "only", "until", "succeeds", "success"]),
        RuleCue(rule: .lastHealthcheckWins, affirms: true, topic: instructions, phrases: lastPhrases,
                topicFirst: false),
        RuleCue(rule: .everyHealthcheckRuns, affirms: true, topic: instructions, phrases: everyPhrases,
                topicFirst: false),
        RuleCue(rule: .earlierOptionsCarryOver, affirms: true, topic: carriedOptions, phrases: carryPhrases,
                topicFirst: false),
        RuleCue(rule: .timeoutStopsContainer, affirms: true, topic: timeout, phrases: stopPhrases, topicFirst: false),
        RuleCue(rule: .timeoutIsFailure, affirms: true, topic: timeout, phrases: failurePhrases, topicFirst: false)
    ]

    static let overrideCues: [RuleCue] = [
        RuleCue(rule: .unsetFieldsKeepImage, affirms: true, topic: partialOverride, phrases: keepPhrases),
        RuleCue(rule: .unsetFieldsDropImage, affirms: true, topic: partialOverride, phrases: dropPhrases),
        RuleCue(rule: .composeCanDisableImage, affirms: true, topic: disabling,
                phrases: ["turns off", "turn off", "disables", "switches off", "switch off", "removes", "overrides",
                          "gets rid of"]),
        // Without `disable` or `NONE` in the clause, only a statement of what compose can do counts.
        RuleCue(rule: .composeCanDisableImage, affirms: true, topic: composeCapability,
                phrases: ["can't turn off", "cannot turn off", "can't disable", "cannot disable", "can't override",
                          "cannot override", "can't remove", "cannot remove", "can turn off", "can disable"])
    ]

    static let variableCues: [RuleCue] = [
        RuleCue(rule: .variableFromContainer, affirms: true, topic: { variable($0, escaped: false) },
                phrases: fromContainerPhrases, topicFirst: false),
        RuleCue(rule: .variableFromShell, affirms: true, topic: { variable($0, escaped: false) },
                phrases: fromShellPhrases, topicFirst: false),
        RuleCue(rule: .escapedFromContainer, affirms: true, topic: { variable($0, escaped: true) },
                phrases: fromContainerPhrases, topicFirst: false),
        RuleCue(rule: .escapedFromShell, affirms: true, topic: { variable($0, escaped: true) },
                phrases: fromShellPhrases, topicFirst: false)
    ]

    static let retriesCues: [RuleCue] = [
        RuleCue(rule: .retriesZeroFailsFast, affirms: true, topic: retriesZero, phrases: failFastPhrases,
                topicFirst: false, allowsInstruction: true),
        RuleCue(rule: .retriesZeroIsDefault, affirms: true, topic: retriesZero, phrases: unsetPhrases,
                topicFirst: false, allowsInstruction: true)
    ]
}
