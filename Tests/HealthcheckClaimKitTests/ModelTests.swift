@testable import HealthcheckClaimKit
import Testing

@Suite("The healthcheck model")
struct ModelTests {
    let image = Healthcheck(test: ["CMD-SHELL", "check"], interval: 7, timeout: 4, startPeriod: 11, startInterval: 3,
                            retries: 6)

    @Test func mergeFillsUnsetFields() {
        #expect(Healthcheck(interval: 2).merged(over: image)
            == Healthcheck(test: ["CMD-SHELL", "check"], interval: 2, timeout: 4, startPeriod: 11, startInterval: 3,
                           retries: 6))
        #expect(Healthcheck(test: []).merged(over: image).test == ["CMD-SHELL", "check"])
        #expect(Healthcheck(test: ["NONE"]).merged(over: image).test == ["NONE"])
        #expect(Healthcheck(test: ["CMD", "x"], retries: 2).merged(over: nil) == Healthcheck(test: ["CMD", "x"],
                                                                                          retries: 2))
    }

    @Test func defaultsAndForms() {
        let unset = Healthcheck(test: ["CMD", "true"])
        #expect(unset.effectiveInterval == 30_000_000_000 && unset.effectiveTimeout == 30_000_000_000)
        #expect(unset.effectiveStartPeriod == 0 && unset.effectiveStartInterval == 5_000_000_000)
        #expect(unset.effectiveRetries == 3 && !unset.runsInShell && !unset.isDisabled)
        #expect(image.effectiveInterval == 7 && image.effectiveTimeout == 4 && image.effectiveStartPeriod == 11)
        #expect(image.effectiveStartInterval == 3 && image.effectiveRetries == 6 && image.runsInShell)
        #expect(Healthcheck().isDisabled && Healthcheck(test: ["NONE"]).isDisabled)
        #expect(unset.summary == "test [\"CMD\", \"true\"], interval 30s, timeout 30s, retries 3, start_period 0s, "
            + "start_interval 5s")
        #expect(Healthcheck().summary.hasPrefix("test []"))
    }

    @Test func settings() {
        #expect(HealthSetting.allCases.map(\.flag)
            == ["--interval", "--timeout", "--retries", "--start-period", "--start-interval"])
        #expect(HealthSetting.allCases.map(\.defaultValue) == [30_000_000_000, 30_000_000_000, 3, 0, 5_000_000_000])
        #expect(HealthSetting.retries.written(3) == "3" && HealthSetting.interval.written(30_000_000_000) == "30s")
        #expect(!HealthSetting.retries.isDuration && HealthSetting.startPeriod.isDuration)
    }

    @Test func effectiveNeedsTheImage() {
        var service = HealthService(name: "web")
        #expect(service.effective(image: .unknown) == nil)
        #expect(service.effective(image: .known(image)) == image)
        service.healthcheck = Healthcheck(interval: 2)
        #expect(service.effective(image: .unknown) == nil)
        service.healthcheck = Healthcheck(test: ["CMD", "x"])
        #expect(service.effective(image: .unknown) == Healthcheck(test: ["CMD", "x"]))
        #expect(service.effective(image: .known(nil)) == Healthcheck(test: ["CMD", "x"]))
    }

    @Test func problemClasses() {
        #expect(FileProblem.allCases.filter(\.isRefused).count == 6)
        #expect(FileProblem.allCases.filter(\.isWrong).count == 9)
        let finding = FileFinding(problem: .retriesZero, service: "db", line: 3, detail: "0")
        #expect(finding.source.isEmpty && finding.line == 3)
    }
}
