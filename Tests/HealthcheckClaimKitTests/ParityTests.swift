@testable import HealthcheckClaimKit
import Testing

struct ParityCase: Sendable, CustomTestStringConvertible {
    enum Stage: Sendable {
        case config
        case build
        case create
    }

    enum Expected: Sendable {
        /// Compose (`config`), `docker build` or the engine (`create`) stopped, with this message.
        case refused(Stage, String)
        /// The container has no healthcheck at all.
        case none
        case healthcheck(Healthcheck)
    }

    let name: String
    let compose: String
    let dockerfile: String
    let dotEnv: String
    let shell: [String: String]
    let expected: Expected

    var testDescription: String {
        name
    }

    /// The case written the way an answer shows it.
    var answer: String {
        var text = "```yaml\n\(compose)```\n\n```dockerfile\n\(dockerfile)```\n"
        if !dotEnv.isEmpty { text += "\n```ini title=\".env\"\n\(dotEnv)```\n" }
        if !shell.isEmpty {
            let exports = shell.sorted { $0.key < $1.key }.map { "export \($0.key)=\($0.value)" }
            text += "\n```sh\n" + exports.joined(separator: "\n") + "\n```\n"
        }
        return text
    }
}

/// Every case of `Scripts/parity.py`, as Docker Compose and the engine answered it.
@Suite("Parity with Docker Compose and the engine")
struct ParityTests {
    /// Cases whose YAML this reader declines to read (a flow mapping holding a flow sequence): no answer, no
    /// misreading.
    static let unfollowed: Set<String> = ["flowMap"]

    @Test(arguments: parityCases)
    func matchesDocker(_ row: ParityCase) {
        let scene = HealthClaimChecker().scene(for: row.answer)
        if Self.unfollowed.contains(row.name) {
            #expect(scene.project == nil)
            return
        }
        let refused = scene.project?.service("web")?.problems.contains(where: \.problem.isRefused) ?? false
        switch row.expected {
        case .refused(.build, _):
            #expect(scene.image == .unknown)
        case .refused:
            #expect(refused)
        case .none:
            #expect(!refused)
            #expect(scene.effective("web") == nil)
        case let .healthcheck(expected):
            #expect(!refused)
            #expect(scene.effective("web") == expected)
        }
    }

    @Test func coversEveryStage() {
        let stages = parityCases.compactMap { row -> String? in
            if case let .refused(stage, _) = row.expected { return "\(stage)" }
            return nil
        }
        #expect(Set(stages) == ["config", "build", "create"])
        #expect(parityCases.count >= 100)
    }
}
