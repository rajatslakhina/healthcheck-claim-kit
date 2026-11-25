@testable import HealthcheckClaimKit
import Testing

@Suite("Stated defaults")
struct DefaultTests {
    let checker = HealthClaimChecker()

    func defaults(_ text: String) -> [String] {
        checker.check(text).findings.compactMap { finding in
            if case let .defaultValue(setting, stated) = finding.claim.kind {
                return "\(setting.rawValue)=\(stated):\(finding.severity)"
            }
            return nil
        }
    }

    @Test func valuesAndUnits() {
        #expect(defaults("The healthcheck `--start-period` defaults to 0.") == ["start_period=0:holds"])
        #expect(defaults("The healthcheck `timeout:` is 30 seconds by default.") == ["timeout=30000000000:holds"])
        #expect(defaults("By default the healthcheck `interval` is half a minute.").isEmpty)
        #expect(defaults("The healthcheck `interval` defaults to 1 minute.") == ["interval=60000000000:wrong"])
        #expect(defaults("The healthcheck `start_interval` defaults to 2.5 sec.")
            == ["start_interval=2500000000:wrong"])
        #expect(defaults("The healthcheck `retries` defaults to three.") == ["retries=3:holds"])
        #expect(defaults("The healthcheck `retries` defaults to 90s.").isEmpty)
        #expect(defaults("The healthcheck `interval` isn't 5s by default.").isEmpty)
        #expect(defaults("The healthcheck `timeout` default is 2m.") == ["timeout=120000000000:wrong"])
        #expect(defaults("Docker's `interval` defaults to 30s.").isEmpty)
    }

    @Test func wordingNamesTheOtherDefault() {
        #expect(Wording.defaultValue(.interval, 5_000_000_000)
            == "The default `interval` is 30s, not 5s (5s is `start_interval`'s default).")
        #expect(Wording.defaultValue(.retries, 5) == "The default `retries` is 3, not 5.")
        #expect(DefaultReader.setting("--start-interval") == .startInterval)
        #expect(DefaultReader.setting("retries:") == .retries && DefaultReader.setting("x") == nil)
        #expect(DefaultReader.count(["many"]) == nil && DefaultReader.duration(["x"]) == nil)
    }
}
