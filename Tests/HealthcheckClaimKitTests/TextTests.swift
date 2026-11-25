@testable import HealthcheckClaimKit
import Testing

@Suite("Text helpers")
struct TextTests {
    @Test func words() {
        #expect(Words.contains("it runs, run it", "run"))
        #expect(!Words.contains("rerun", "run"))
        #expect(Words.contains("a `&&` b", "`&&`"))
        #expect(Words.firstPosition("b a", ["a", "b"]) == "b a".startIndex)
        #expect(Words.firstPosition("x", ["a"]) == nil)
        #expect(!Words.isWord(nil))
    }

    @Test func blocksAndSentences() {
        let blocks = AnswerBlocks.split("Intro.\n```yaml\na: 1\n```\nMiddle.\n~~~\nopen")
        #expect(blocks.count == 4)
        #expect(blocks[1].kind == .code(info: "yaml") && blocks[1].text == "a: 1")
        #expect(Sentences.split(["It runs `app.js`. Then e.g. this! Done?", "", "Last"])
            == ["It runs `app.js`.", "Then e.g. this!", "Done?", "Last"])
        #expect(Sentences.codeSpans("a `b` c `d`") == ["b", "d"])
        #expect(Sentences.clauses("`a; b` runs, but `c` is fine; d") == ["`a; b` runs", "`c` is fine", "d"])
        #expect(Sentences.negationCount("it doesn't and won't, not never") == 4)
    }

    @Test func clauses() {
        let clause = Clause("Note that also `$$HOME` is set")
        #expect(clause.text == "`$$HOME` is set")
        #expect(clause.variableToken == "$$HOME")
        #expect(Clause("Use `sh -c`").isInstruction)
        #expect(!Clause("It runs").isInstruction)
        #expect(Clause("You might expect it to run").isHypothetical)
        #expect(Clause.isVariable("${A:-b}") && Clause.isVariable("$${A}") && !Clause.isVariable("${1}")
            && !Clause.isVariable("${A") && !Clause.isVariable("A") && !Clause.isVariable("$A b"))
        #expect(Clause.variableName("$${A}") == ("A", true))
        #expect(Clause.variableName("$B") == ("B", false))
    }
}
