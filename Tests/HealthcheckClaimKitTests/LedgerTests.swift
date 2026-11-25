@testable import HealthcheckClaimKit
import Testing

@Suite("One conversation")
struct LedgerTests {
    let file = """
    ```yaml
    services:
      db:
        environment:
          POSTGRES_USER: app
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]
    ```
    """

    @Test func repeatsAndCarriedFiles() async {
        let ledger = HealthLedger()
        let first = await ledger.review(file + "\nDocker restarts the container when it is unhealthy.")
        #expect(first.flagged.count == 2 && first.repeatedCount == 0)
        let second = await ledger.review("Again: an unhealthy container is restarted by Docker.")
        #expect(second.repeatedCount == 1)
        let third = await ledger.review("The string form runs through a shell.")
        #expect(third.verdict == .verified)
        let statistics = await ledger.statistics
        #expect(statistics == HealthLedger.Statistics(reviews: 3, claims: 4, flagged: 3, repeated: 1))
        await ledger.forget()
        let fresh = await ledger.review("The string form runs through a shell.")
        #expect(fresh.verdict == .noClaims)
    }

    @Test func checkerSurface() {
        let checker = HealthClaimChecker()
        let claims = checker.claims(in: "Docker restarts unhealthy containers.")
        #expect(claims.count == 1)
        #expect(checker.judge(claims[0]).severity == .wrong)
        let scene = checker.scene(for: file)
        #expect(scene.showsHealthcheck && scene.aboutDocker && scene.project?.services.count == 1)
        #expect(scene.effective("db") == Healthcheck(test: ["CMD-SHELL", "pg_isready -U "]))
        #expect(scene.effective("web") == nil)
        #expect(HealthClaimChecker().reader.claims(in: "Nothing here.", scene: HealthScene()).isEmpty)
    }

    @Test func envBlocksNeedTheirName() {
        let checker = HealthClaimChecker()
        let named = checker.scene(for: "Put this in `.env`:\n```\nA=1\n```\nThen:\n```\nB=2\n```")
        #expect(named.variables.dotEnv == ["A": "1"])
    }

    @Test func earlierTurnsCarryTheImage() async {
        let ledger = HealthLedger()
        _ = await ledger.review("```dockerfile\nFROM scratch\nHEALTHCHECK --retries=6 CMD check\n```\n"
                                + "```yaml\nservices:\n  web:\n    build: .\n    healthcheck:\n      interval: 2s\n```")
        let report = await ledger.review("Fine.", context: "Thanks.")
        #expect(report.verdict == .noClaims)
    }
}
