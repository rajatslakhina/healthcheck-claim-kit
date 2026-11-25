@testable import HealthcheckClaimKit
import Testing

@Suite("Rules stated in prose")
struct RuleTests {
    let checker = HealthClaimChecker()

    func rules(_ text: String, context: String = "") -> [String] {
        checker.check(text, context: context).findings.compactMap { finding in
            if case let .rule(rule, affirmed) = finding.claim.kind { return "\(rule.rawValue)=\(affirmed)" }
            return nil
        }
    }

    @Test func eachRuleIsRead() {
        let docker = "In Docker, "
        #expect(rules(docker + "the exec form of the healthcheck goes through a shell.") == ["execFormUsesShell=true"])
        #expect(rules(docker + "`CMD-SHELL` is run by a shell.") == ["stringFormUsesShell=true"])
        #expect(rules(docker + "an unhealthy container is restarted.") == ["unhealthyRestarts=true"])
        #expect(rules(docker + "the check runs on your machine.") == ["runsInContainer=false"])
        #expect(rules(docker + "failures in the healthcheck `start_period` are counted.")
            == ["startPeriodFailuresCount=true"])
        #expect(rules("Compose's `retries` comes from the image if unset.") == ["unsetFieldsDropImage=false"])
        #expect(rules(docker + "setting `timeout` inherits the image's `HEALTHCHECK` command.")
            == ["unsetFieldsDropImage=false"])
        #expect(rules(docker + "the healthcheck `disable: true` removes the image's check.")
            == ["composeCanDisableImage=true"])
        #expect(rules("The second `HEALTHCHECK` line overrides the earlier one in the Dockerfile.")
            == ["everyHealthcheckRuns=false"])
        #expect(rules("With two `HEALTHCHECK` lines the `--retries` carries over.")
            == ["earlierOptionsCarryOver=true"])
        #expect(rules(docker + "a healthcheck that times out restarts the container.") == ["timeoutIsFailure=false"])
        #expect(rules(docker + "the healthcheck's `$$HOST` is expanded by the container's shell.")
            == ["escapedFromContainer=true"])
        #expect(rules(docker + "the healthcheck's `$$HOST` is substituted when compose reads the file.")
            == ["escapedFromContainer=false"])
        #expect(rules(docker + "the healthcheck's `$HOST` is substituted from your shell.")
            == ["variableFromContainer=false"])
        #expect(rules("In compose, `retries: 0` falls back to 3.") == ["retriesZeroFailsFast=false"])
    }

    @Test func polarityAndGuards() {
        #expect(rules("In Docker the healthcheck doesn't always run on the host.") == ["runsInContainer=true"])
        #expect(rules("Docker does not restart the unhealthy container it never sees.").isEmpty)
        #expect(rules("Docker restarts it if it is unhealthy, not if it exits.").isEmpty)
        #expect(rules("Use the shell form, since the healthcheck string goes through a shell.")
            == ["stringFormUsesShell=true"])
        #expect(rules("Make the healthcheck run inside the container.").isEmpty)
        #expect(rules("You'd think Docker restarts unhealthy containers.").isEmpty)
        #expect(rules("The healthcheck runs in the container and runs on the host.").isEmpty)
        #expect(rules("In Kubernetes the healthcheck of an unhealthy pod is restarted.").isEmpty)
        #expect(rules("The healthcheck `command:` goes through a shell.") == ["stringFormUsesShell=true"]
            || rules("The healthcheck `command:` goes through a shell.").isEmpty)
        #expect(rules("Docker's `command:` string runs in a shell.").isEmpty)
        #expect(rules("The unhealthy check restarts nothing.", context: "no docker here").isEmpty)
    }

    @Test func bareCMDNeedsAHealthcheckInView() {
        let healthcheck = "```yaml\nservices:\n  web:\n    healthcheck:\n      test: [\"CMD\", \"true\"]\n```"
        #expect(rules("In Docker, the `CMD` form goes through a shell.").isEmpty)
        #expect(rules("The `CMD` form goes through a shell.", context: healthcheck) == ["execFormUsesShell=true"])
        #expect(rules("The `[\"CMD\", \"sh\", \"-c\", \"x\"]` list runs through a shell.", context: healthcheck).isEmpty)
        #expect(rules("The string form runs through a shell.", context: healthcheck) == ["stringFormUsesShell=true"])
        #expect(rules("Docker's `HEALTHCHECK CMD [\"a\"]` uses the shell form.") == [])
        #expect(rules("In compose, a `test: [\"CMD\", \"a\"]` uses the shell form.") == ["execFormUsesShell=true"])
    }

    @Test func canonicalFormsAndHolds() {
        #expect(Rule.allCases.filter(\.holds).count == 9)
        #expect(Rule.execFormUsesShell.opposite == nil)
        #expect(Rule.runsOnHost.canonical(affirmed: true) == (.runsInContainer, false))
        #expect(Rule.runsInContainer.canonical(affirmed: true) == (.runsInContainer, true))
    }
}
