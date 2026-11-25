@testable import HealthcheckClaimKit
import Testing

@Suite("Variables compose substitutes")
struct InterpolationTests {
    let variables = Variables(shell: ["HOME": "/Users/x", "EMPTY": ""], dotEnv: ["GREETING": "hi", "HOME": "/env"],
                              unset: ["GONE"])

    @Test(arguments: [
        ("echo $HOME", "echo /Users/x"), ("echo ${HOME}/x", "echo /Users/x/x"), ("$$HOME $$ $", "$HOME $ $"),
        ("$(date)", "$(date)"), ("${GONE:-d}", "d"), ("${EMPTY:-d}", "d"), ("${EMPTY-d}", ""), ("${GONE-d}", "d"),
        ("${GREETING:+set}", "set"), ("${EMPTY:+set}", ""), ("${EMPTY+set}", "set"), ("${GONE+set}", ""),
        ("${GREETING:?no}", "hi"), ("${EMPTY?no}", ""), ("${GONE:-${GREETING}}", "hi"), ("$GONE", "")
    ])
    func resolves(_ row: (String, String)) throws {
        #expect(try Interpolation.resolve(row.0, variables).value == row.1)
    }

    @Test func unknownNames() throws {
        let result = try Interpolation.resolve("echo $TAG ${OTHER:-x} $HOME", variables)
        #expect(result.unknown == ["TAG", "OTHER"])
        #expect(result.value == "echo  x /Users/x")
    }

    @Test(arguments: ["${GONE:?message}", "${EMPTY:?message}", "${GONE?message}"])
    func required(_ text: String) {
        #expect(throws: Interpolation.Failure.self) { try Interpolation.resolve(text, variables) }
    }

    @Test func requiredButUnseen() throws {
        let result = try Interpolation.resolve("${TAG:?set TAG}", variables)
        #expect(result.value == "" && result.unknown == ["TAG"])
    }

    @Test(arguments: ["$1", "$-", "${", "${1}", "${A", "${A*b}"])
    func malformed(_ text: String) {
        #expect(throws: Interpolation.Failure.malformed) { try Interpolation.resolve(text, variables) }
    }

    @Test func names() {
        #expect(Interpolation.names(in: "echo $A ${B:-x} $$C $A $") == ["A", "B"])
        #expect(Interpolation.escapedNames(in: "echo $$A $${B} $C $$ $$1") == ["A", "B"])
    }

    @Test func envFile() {
        let values = EnvFile.parse(["# c", "", "export A=1", "B = two # note", "C='x # y'", "D=\"q\"", "E=\"$X\"",
                                    "F=$Y", "noequals", "1BAD=x", "G='open", "H="])
        #expect(values == ["A": "1", "B": "two", "C": "x # y", "D": "q", "H": ""])
        #expect(EnvFile.looksLikeEnvFile(["# c", "A=1"]))
        #expect(!EnvFile.looksLikeEnvFile(["# only"]))
        #expect(!EnvFile.looksLikeEnvFile(["A=1", "echo hi"]))
        #expect(!EnvFile.looksLikeEnvFile(["1A=1"]))
    }
}
