@testable import HealthcheckClaimKit
import Testing

@Suite("File-line checks")
struct FileCheckTests {
    let checker = HealthClaimChecker()

    func problems(_ yaml: String, context: String = "") -> [FileProblem] {
        checker.check("```yaml\n\(yaml)\n```", context: context).findings.compactMap { finding in
            if case let .file(file) = finding.claim.kind { return file.problem }
            return nil
        }
    }

    @Test func publishedPortRetriesAndDisable() {
        #expect(problems("""
        services:
          web:
            ports: ["8080:80"]
            healthcheck:
              test: curl -f http://localhost:8080/health
              retries: 0
              disable: true
        """) == [.publishedPortInTest, .disableWithTest, .retriesZero])
        #expect(problems("""
        services:
          web:
            ports: ["8080:80", "80:80"]
            healthcheck:
              test: curl -f http://localhost:80/ && curl http://127.0.0.1:x
        """).isEmpty)
        #expect(problems("""
        services:
          web:
            ports: ["9000:80"]
            healthcheck:
              test: curl -f http://0.0.0.0:7000/
        """).isEmpty)
    }

    @Test func variablesAndShells() {
        #expect(problems("""
        services:
          db:
            environment: {U: app, V: x}
            healthcheck:
              test: ["CMD", "sh", "-c", "pg_isready -U $$U && echo $U $U ${V:-v}"]
        """) == [.containerVariable])
        #expect(FileChecks.startsShell(["/bin/bash", "-c", "x"]) && !FileChecks.startsShell(["sh"]))
        #expect(!FileChecks.startsShell(["python", "-c", "x"]))
        #expect(FileChecks.testProblems([], isString: false).isEmpty)
        #expect(FileChecks.testProblems(["NONE"], isString: false).isEmpty)
        #expect(FileChecks.lineProblems(.scalar("x"), service: HealthService(name: "a"), variables: Variables(),
                                        lines: []).isEmpty)
    }

    @Test func quotedLinesAreNotChecked() {
        let question = "```yaml\nservices:\n  web:\n    healthcheck:\n      test: [\"CMD-SHELL\", \"a\", \"b\"]\n```"
        #expect(problems("services:\n  api:\n    healthcheck:\n      test: [\"CMD-SHELL\", \"a\", \"b\"]",
                         context: question).isEmpty)
        let report = checker.check("```dockerfile\nFROM scratch\nHEALTHCHECK CMD [\"a\", \"&&\", \"b\"]\n```")
        #expect(report.verdict == .wrong)
        #expect(report.corrections == ["line 2: `&&` in the exec form reaches the program as an argument, not as a "
            + "shell operator; use `CMD-SHELL` or a string `test:`."])
    }

    @Test func onlyTheAnswersLastFileIsChecked() {
        let answer = """
        ```yaml
        services:
          web:
            healthcheck:
              test: ["curl"]
        ```
        ```yaml
        services:
          web:
            healthcheck:
              test: ["CMD", "curl"]
        ```
        """
        #expect(checker.check(answer).findings.isEmpty)
    }
}
