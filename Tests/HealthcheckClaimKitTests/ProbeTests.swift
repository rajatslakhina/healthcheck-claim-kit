@testable import HealthcheckClaimKit
import Testing

/// The probe corpus, written before the reader from real answer shapes: correct answers stay quiet, wrong ones are
/// flagged, sentences from other domains give no claims at all.
@Suite("Probe corpus")
struct ProbeTests {
    let checker = HealthClaimChecker()

    func describe(_ report: HealthReport) -> String {
        report.findings.map { "\($0.severity) \($0.claim.kind) [\($0.claim.sentence)]" }.joined(separator: "\n")
    }

    @Test(arguments: correctProbes + laterCorrectProbes)
    func correctAnswersStayQuiet(_ probe: Probe) {
        let report = checker.check(probe.answer, context: probe.question)
        #expect(report.flagged.isEmpty, "\(probe.name):\n\(describe(report))")
    }

    @Test(arguments: wrongProbes + laterProbes)
    func wrongAnswersAreFlagged(_ probe: Probe) {
        let report = checker.check(probe.answer, context: probe.question)
        #expect(!report.flagged.isEmpty, "\(probe.name):\n\(describe(report))")
    }

    @Test(arguments: otherDomainProbes)
    func otherDomainsGiveNoClaims(_ probe: Probe) {
        let report = checker.check(probe.answer, context: probe.question)
        #expect(report.findings.isEmpty, "\(probe.name):\n\(describe(report))")
    }
}
