/// The corrections people read.
enum Wording {
    static func rule(_ rule: Rule) -> String {
        switch rule {
        case .execFormUsesShell, .stringFormUsesShell, .unhealthyRestarts, .runsInContainer, .runsOnHost,
             .startPeriodFailuresCount, .timeoutIsFailure, .timeoutStopsContainer:
            runtime(rule)
        default:
            settings(rule)
        }
    }

    /// How the engine runs a check.
    static func runtime(_ rule: Rule) -> String {
        switch rule {
        case .execFormUsesShell:
            "The exec form (`[\"CMD\", ...]`) runs the program directly, with no shell: `||`, `&&` and `$VAR` reach "
                + "it as plain arguments. Use `CMD-SHELL` or a string `test:` for shell syntax."
        case .stringFormUsesShell:
            "A string `test:` (like `CMD-SHELL` and the Dockerfile's shell form) runs through `/bin/sh -c`, unlike a "
                + "compose `command:` string."
        case .unhealthyRestarts:
            "Docker does not restart an unhealthy container, whatever the restart policy: it only marks it "
                + "`unhealthy`. A restart policy acts when the main process exits; Swarm and tools such as autoheal "
                + "act on health, plain Docker and compose do not."
        case .runsInContainer, .runsOnHost:
            "The healthcheck runs inside the container, like `docker exec`: it uses the container's tools, and "
                + "`localhost` there is the container."
        case .startPeriodFailuresCount:
            "Failures during `start_period` are not counted toward `retries`; a success during it marks the "
                + "container healthy and ends the start period."
        default:
            "A check that runs past `timeout` is stopped and counts as one failed check; the container keeps "
                + "running and turns `unhealthy` after `retries` failures in a row."
        }
    }

    /// How settings, images and variables combine.
    static func settings(_ rule: Rule) -> String {
        switch rule {
        case .unsetFieldsDropImage, .unsetFieldsKeepImage:
            "The engine fills every field a compose `healthcheck:` leaves out from the image's `HEALTHCHECK`: "
                + "setting only `interval` keeps the image's test, timeout and retries."
        case .composeCanDisableImage:
            "`disable: true` (or `test: [\"NONE\"]`) turns off a `HEALTHCHECK` the image defines."
        case .everyHealthcheckRuns, .lastHealthcheckWins:
            "Only the last `HEALTHCHECK` in a Dockerfile takes effect; each one replaces the one before."
        case .earlierOptionsCarryOver:
            "A `HEALTHCHECK` replaces the earlier one entirely: options it does not repeat go back to their "
                + "defaults, they are not kept from the first."
        case .variableFromContainer, .variableFromShell:
            "Compose substitutes `$NAME` in `test:` from the shell and `.env` when it reads the file, not from the "
                + "container's `environment:`; write `$$NAME` for the container's shell to expand it."
        case .escapedFromContainer, .escapedFromShell:
            "`$$NAME` is how compose writes a literal `$`: the container gets `$NAME`, and its shell (in "
                + "`CMD-SHELL`) expands it."
        default:
            "`retries: 0` is the same as leaving it out: the image's value, else 3 failures in a row."
        }
    }

    static func defaultValue(_ setting: HealthSetting, _ stated: Int64) -> String {
        let other = HealthSetting.allCases.first { $0 != setting && $0.isDuration == setting.isDuration
            && $0.defaultValue == stated }
        let note = other.map { " (\(setting.written(stated)) is `\($0.rawValue)`'s default)" } ?? ""
        return "The default `\(setting.rawValue)` is \(setting.written(setting.defaultValue)), "
            + "not \(setting.written(stated))\(note)."
    }

    static func file(_ finding: FileFinding) -> String {
        let place = (finding.service.isEmpty ? "" : "`\(finding.service)`, ") + "line \(finding.line)"
        return "\(place): " + problem(finding)
    }

    static func problem(_ finding: FileFinding) -> String {
        let detail = finding.detail
        switch finding.problem {
        case .unknownTestType:
            return "`test:` starts with `\(detail)`; compose refuses a list that does not start with `CMD`, "
                + "`CMD-SHELL` or `NONE`."
        case .testWithoutValue:
            return "`test:` has no value; compose refuses it. Write a string or a list starting with `CMD`."
        case .durationNeedsUnit:
            return "`\(detail)` has no unit; compose refuses it. Write a duration such as `30s`."
        case .durationRefused:
            return "compose cannot read `\(detail)` as a duration (units are `ms`, `s`, `m`, `h`, with no spaces)."
        case .durationTooShort:
            return "`\(detail)` is below 1ms; the engine refuses to create the container."
        case .retriesNegative:
            return "`retries: \(detail)` is negative; compose refuses the file."
        case .operatorInExecForm:
            return "`\(detail)` in the exec form reaches the program as an argument, not as a shell operator; "
                + "use `CMD-SHELL` or a string `test:`."
        case .scriptInPieces:
            return "`CMD-SHELL` runs only its first string (`\(detail)`) as the script; the other items become "
                + "`$0`, `$1`. Put the whole command in one string."
        default:
            return variableProblem(finding)
        }
    }

    static func variableProblem(_ finding: FileFinding) -> String {
        let detail = finding.detail
        switch finding.problem {
        case .variableInExecForm:
            return "the exec form has no shell to expand `\(detail)`, so the program gets that text; use "
                + "`CMD-SHELL`."
        case .containerVariable:
            return "compose substitutes `\(detail)` when it reads the file, from the shell and `.env`; the service's "
                + "`environment:` does not count, so the test gets an empty value. Write `$\(detail)` for the "
                + "container's shell to expand it."
        case .publishedPortInTest:
            let published = detail.prefix { $0 != ":" }
            let target = detail.dropFirst(published.count + 1)
            return "the test runs inside the container, where the app listens on \(target), not on the "
                + "published host port \(published)."
        case .retriesZero:
            return "`retries: 0` is the same as leaving it out: the image's value, else 3."
        default:
            return "`disable: true` turns the healthcheck off, so this `test:` never runs."
        }
    }
}
