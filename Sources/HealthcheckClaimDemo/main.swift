import HealthcheckClaimKit

/// Ten answers a model might give about Docker healthchecks, checked against what compose and the engine do with
/// them. Every expectation printed here was probed with `docker compose config`, `docker compose create` +
/// `docker inspect`, and running containers (Docker Compose 2.32.4, Docker Engine 27.4).

let fence = "```"

func show(_ title: String, _ report: HealthReport) {
    print("== \(title)")
    print("   verdict: \(report.verdict.rawValue) (\(report.summary))")
    for finding in report.findings {
        let mark = switch finding.severity {
        case .holds: "holds  "
        case .caution: "caution"
        case .wrong: "WRONG  "
        }
        let repeated = finding.isRepeated ? " [repeated]" : ""
        print("   \(mark) \(finding.claim.sentence)\(repeated)")
        if let correction = finding.correction { print("           -> \(correction)") }
    }
}

let checker = HealthClaimChecker()

let brokenQuestion = """
My web container never turns healthy:

\(fence)yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost", "||", "exit", "1"]
\(fence)
"""
show("1. the exec form read as a shell", checker.check("""
Your test is fine: Docker runs the healthcheck through a shell, so the `||` works.
""", context: brokenQuestion))
show("1b. the fix: CMD-SHELL", checker.check("""
The exec form runs `curl` directly, so `||` reaches it as an argument. Use a shell:

\(fence)yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost || exit 1"]
\(fence)

A `CMD-SHELL` test is run by a shell.
""", context: brokenQuestion))

show("2. a variable compose substitutes", checker.check("""
`$POSTGRES_USER` in the healthcheck comes from the container's environment:

\(fence)yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_USER: app
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]
\(fence)
"""))

show("3. unhealthy is not restarted", checker.check("""
Add `restart: always` and Docker restarts the container when it becomes unhealthy.
"""))

show("4. defaults", checker.check("""
If you leave them out, the healthcheck `interval` defaults to 5s and `retries` to 3.
"""))

let image = """
\(fence)dockerfile
FROM scratch
HEALTHCHECK --interval=7s --retries=6 CMD /bin/check
\(fence)
\(fence)yaml
services:
  web:
    build: .
    healthcheck:
      interval: 2s
\(fence)
"""
let scene = checker.scene(for: image)
print("== 5. merged with the image's HEALTHCHECK")
print("   web runs: \(scene.effective("web")?.summary ?? "unknown")")
show("5b. a claim about that merge", checker.check(
    "Setting only `interval` in compose means the image's `HEALTHCHECK` command is dropped.", context: image))

show("6. files compose or the engine refuse", checker.check("""
\(fence)yaml
services:
  web:
    image: nginx:1.27
    healthcheck:
      test: ["curl", "-f", "http://localhost"]
      interval: 30
  worker:
    image: myorg/worker:3
    healthcheck:
      test: ["CMD-SHELL", "pgrep", "-f", "worker"]
      timeout: 500us
\(fence)
"""))

show("7. a Dockerfile exec form", checker.check("""
\(fence)dockerfile
FROM python:3.13-slim
HEALTHCHECK CMD ["curl", "-f", "http://localhost:8000/health", "||", "exit", "1"]
\(fence)
"""))

show("8. other systems' health checks stay out", checker.check("""
In Kubernetes a failing liveness probe restarts the container. AWS ALB health checks run every 30 seconds by default.
"""))

show("9. a correct answer is verified", checker.check("""
The healthcheck runs inside the container, failures during `start_period` don't count toward `retries`, and a \
check that runs past `timeout` counts as a failure.
"""))

let ledger = HealthLedger()
show("10a. a conversation", await ledger.review("""
Docker restarts unhealthy containers on its own.
""", context: "Does Docker restart my unhealthy container?"))
show("10b. the same mistake again", await ledger.review("""
As I said, an unhealthy container is restarted by Docker.
"""))
let statistics = await ledger.statistics
print("== ledger: \(statistics.reviews) reviews, \(statistics.claims) claims, \(statistics.flagged) flagged, "
    + "\(statistics.repeated) repeated")
