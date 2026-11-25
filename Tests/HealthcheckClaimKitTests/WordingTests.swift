@testable import HealthcheckClaimKit
import Testing

@Suite("Reports and wording")
struct WordingTests {
    @Test func everyRuleAndProblemHasWords() {
        for rule in Rule.allCases {
            #expect(!Wording.rule(rule).isEmpty)
        }
        for problem in FileProblem.allCases {
            let text = Wording.file(FileFinding(problem: problem, service: "web", line: 4, detail: "8080:80"))
            #expect(text.hasPrefix("`web`, line 4: "))
        }
        #expect(Wording.file(FileFinding(problem: .publishedPortInTest, service: "", line: 2, detail: "8080:80"))
            == "line 2: the test runs inside the container, where the app listens on 80, not on the published "
            + "host port 8080.")
    }

    @Test func verdicts() {
        let claim = HealthClaim(kind: .rule(.runsInContainer, affirmed: true), sentence: "s")
        let holds = HealthFinding(claim: claim, severity: .holds, correction: nil)
        let caution = HealthFinding(claim: claim, severity: .caution, correction: "c")
        let wrong = HealthFinding(claim: claim, severity: .wrong, correction: "w")
        #expect(HealthReport(findings: []).verdict == .noClaims)
        #expect(HealthReport(findings: [holds]).verdict == .verified)
        #expect(HealthReport(findings: [holds, caution]).verdict == .caution)
        let report = HealthReport(findings: [caution, wrong, holds])
        #expect(report.verdict == .wrong && report.corrections == ["c", "w"])
        #expect(report.summary == "wrong: 3 claim(s), 1 wrong, 1 caution")
        #expect(HealthFinding.Severity.holds < .caution && HealthReport.Verdict.allCases.count == 4)
    }

    @Test func repeatKeys() {
        let file = FileFinding(problem: .retriesZero, service: "a", line: 1, detail: "0")
        #expect(HealthClaim(kind: .file(file), sentence: "").repeatKey == "file:retriesZero:0")
        #expect(HealthClaim(kind: .defaultValue(.retries, stated: 5), sentence: "").repeatKey == "default:retries:5")
        #expect(HealthClaim(kind: .rule(.runsOnHost, affirmed: false), sentence: "").repeatKey
            == "rule:runsOnHost:false")
    }
}
