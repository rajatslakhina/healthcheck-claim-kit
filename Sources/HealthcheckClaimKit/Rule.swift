/// A general statement about how Docker runs healthchecks, settled against the engine and compose.
public enum Rule: String, Sendable, Hashable, CaseIterable {
    /// `["CMD", ...]` runs through a shell. Wrong: the engine execs the program; `||` reaches it as an argument.
    case execFormUsesShell
    /// A string `test:`, `CMD-SHELL` and the Dockerfile's shell form run through `/bin/sh -c`. Holds.
    case stringFormUsesShell
    /// The engine restarts an unhealthy container (with a restart policy). Wrong: it only marks it unhealthy.
    case unhealthyRestarts
    /// The test runs on the host. Wrong: it runs inside the container, with the container's tools and network.
    case runsOnHost
    /// The test runs inside the container. Holds.
    case runsInContainer
    /// Failures during `start_period` count toward `retries`. Wrong: they are not counted.
    case startPeriodFailuresCount
    /// Settings a compose `healthcheck:` leaves out keep the image's `HEALTHCHECK` values. Holds.
    case unsetFieldsKeepImage
    /// Setting some fields in compose drops the image's command or other values. Wrong.
    case unsetFieldsDropImage
    /// `disable: true` or `test: ["NONE"]` turns off the image's `HEALTHCHECK`. Holds.
    case composeCanDisableImage
    /// Only the last `HEALTHCHECK` in a Dockerfile takes effect. Holds.
    case lastHealthcheckWins
    /// Every `HEALTHCHECK` in a Dockerfile runs. Wrong.
    case everyHealthcheckRuns
    /// A later `HEALTHCHECK` keeps an earlier one's options. Wrong: it replaces all of them.
    case earlierOptionsCarryOver
    /// A test that runs past `timeout` stops or restarts the container. Wrong: it counts as one failed check.
    case timeoutStopsContainer
    /// A test that runs past `timeout` counts as a failed check. Holds.
    case timeoutIsFailure
    /// `$NAME` in `test:` is read from the container's environment. Wrong: compose substitutes it from the shell
    /// and `.env` when it reads the file.
    case variableFromContainer
    /// `$NAME` in `test:` is substituted by compose from the shell and `.env`. Holds.
    case variableFromShell
    /// `$$NAME` reaches the container, whose shell expands it. Holds.
    case escapedFromContainer
    /// `$$NAME` is substituted by compose. Wrong: `$$` is a literal `$`.
    case escapedFromShell
    /// `retries: 0` makes the first failure mark the container unhealthy. Wrong: 0 means unset.
    case retriesZeroFailsFast
    /// `retries: 0` is the same as not setting it. Holds.
    case retriesZeroIsDefault

    public var holds: Bool {
        switch self {
        case .stringFormUsesShell, .runsInContainer, .unsetFieldsKeepImage, .composeCanDisableImage,
             .lastHealthcheckWins, .timeoutIsFailure, .variableFromShell, .escapedFromContainer, .retriesZeroIsDefault:
            true
        default:
            false
        }
    }

    /// The rule that says the opposite, when there is one.
    var opposite: Rule? {
        Self.opposites[self]
    }

    static let opposites: [Rule: Rule] = {
        let pairs: [(Rule, Rule)] = [(.runsOnHost, .runsInContainer), (.unsetFieldsKeepImage, .unsetFieldsDropImage),
                                     (.lastHealthcheckWins, .everyHealthcheckRuns),
                                     (.timeoutStopsContainer, .timeoutIsFailure),
                                     (.variableFromContainer, .variableFromShell),
                                     (.escapedFromContainer, .escapedFromShell),
                                     (.retriesZeroFailsFast, .retriesZeroIsDefault)]
        var map: [Rule: Rule] = [:]
        for (first, second) in pairs {
            map[first] = second
            map[second] = first
        }
        return map
    }()

    /// The rule and whether it is stated true, written with the first rule of its pair.
    func canonical(affirmed: Bool) -> (Rule, Bool) {
        guard let opposite, opposite.rawValue < rawValue else { return (self, affirmed) }
        return (opposite, !affirmed)
    }
}
