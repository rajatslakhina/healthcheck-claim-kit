@testable import HealthcheckClaimKit
import Testing

@Suite("Go durations")
struct DurationTests {
    @Test(arguments: [
        ("10s", 10_000_000_000), ("1m30s", 90_000_000_000), ("500ms", 500_000_000), ("1.5s", 1_500_000_000),
        ("0", 0), ("0s", 0), (".5s", 500_000_000), ("5.s", 5_000_000_000), ("+5s", 5_000_000_000),
        ("-5s", -5_000_000_000), ("100us", 100_000), ("100\u{00B5}s", 100_000), ("2\u{03BC}s", 2_000), ("1ns", 1),
        ("1h2m3s4ms", 3_723_004_000_000), ("1.25m", 75_000_000_000)
    ] as [(String, Int64)])
    func parses(_ row: (String, Int64)) throws {
        #expect(try GoDuration.parse(row.0) == row.1)
    }

    @Test func refusals() {
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse("") }
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse("-") }
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse(".s") }
        #expect(throws: GoDuration.Failure.missingUnit) { try GoDuration.parse("30") }
        #expect(throws: GoDuration.Failure.unknownUnit("d")) { try GoDuration.parse("1d") }
        #expect(throws: GoDuration.Failure.unknownUnit("m ")) { try GoDuration.parse("1m 30s") }
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse("9999999999999h") }
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse("9223372036s9223372036s") }
        #expect(throws: GoDuration.Failure.invalid) { try GoDuration.parse("1.9999999999999999999h") }
    }

    @Test(arguments: [
        (0, "0s"), (1, "1ns"), (1_500, "1.5\u{00B5}s"), (500_000_000, "500ms"), (1_500_000_000, "1.5s"),
        (90_000_000_000, "1m30s"), (3_600_000_000_000, "1h0m0s"), (120_000_000_000, "2m0s"), (-5_000_000_000, "-5s"),
        (1_000_000, "1ms"), (3_723_004_000_000, "1h2m3.004s")
    ] as [(Int64, String)])
    func formats(_ row: (Int64, String)) {
        #expect(GoDuration.format(row.0) == row.1)
    }
}
