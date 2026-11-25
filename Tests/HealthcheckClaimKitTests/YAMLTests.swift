@testable import HealthcheckClaimKit
import Testing

@Suite("The YAML subset")
struct YAMLTests {
    @Test func blockMappingsSequencesAndFlow() throws {
        let node = try ComposeYAML.parse("""
        ---
        services:
          web:
            command: ["npm", "run", 'dev']
            entrypoint: {a: 1, b: "x, y"}
            ports:
              - "80:80"
              - target: 80
                published: 8080
            empty: []
            none: ~
            flag:
            'quoted key': value
        """)
        let web = try #require(node["services"]?["web"])
        #expect(web["command"] == .list([.scalar("npm"), .scalar("run"), .scalar("dev")]))
        #expect(web["entrypoint"]?.entries?.map(\.key) == ["a", "b"])
        #expect(web["entrypoint"]?["b"] == .scalar("x, y"))
        #expect(web["ports"]?.items?.count == 2)
        #expect(web["empty"] == .list([]))
        #expect(web["none"] == .null)
        #expect(web["flag"] == .null)
        #expect(web["quoted key"] == .scalar("value"))
        #expect(web.entry("command")?.line == 4)
        #expect(web["missing"] == nil)
        #expect(ComposeNode.scalar("x").items == nil && ComposeNode.scalar("x").entries == nil)
        #expect(ComposeNode.null.text == nil)
    }

    @Test func emptyAndCommentOnly() throws {
        #expect(try ComposeYAML.parse("# only a comment\n\n") == .null)
        #expect(try ComposeYAML.parse("a: x # note")["a"] == .scalar("x"))
        #expect(try ComposeYAML.parse("a: \"x # kept\"")["a"] == .scalar("x # kept"))
        #expect(try ComposeYAML.parse("a: 'it''s # kept'")["a"] == .scalar("it's # kept"))
        #expect(try ComposeYAML.parse("a: \"say \\\"hi\\\" # kept\"")["a"] == .scalar("say \"hi\" # kept"))
        #expect(try ComposeYAML.parse("a: x#y")["a"] == .scalar("x#y"))
        #expect(try ComposeYAML.parse("a: b\"c # d")["a"] == .scalar("b\"c"))
        #expect(try ComposeYAML.parse("- [\"a\", 'b']") == .list([.list([.scalar("a"), .scalar("b")])]))
    }

    @Test func doubleQuotedEscapes() throws {
        #expect(try ComposeYAML.parse("a: \"x\\ny\\tz\\r\\\\\\/\\ \"")["a"] == .scalar("x\ny\tz\r\\/ "))
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse("a: \"\\x41\"") }
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse("a: \"open") }
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse("a: \"x\" y") }
        #expect(ComposeYAML.quoted("\"x\\") == nil)
        #expect(ComposeYAML.quoted("") == nil)
    }

    @Test func blockScalars() throws {
        let node = try ComposeYAML.parse("""
        literal: |
          npm install
          # not a comment

          npm start
        folded: >
          sh -c "npm install
          && npm start"

          next
        strip: |-
          a
        keep: |+
          a

        dash:
          - |
            x
        empty: |
        after: 1
        """)
        #expect(node["literal"] == .scalar("npm install\n# not a comment\n\nnpm start\n"))
        #expect(node["folded"] == .scalar("sh -c \"npm install && npm start\"\nnext\n"))
        #expect(node["strip"] == .scalar("a"))
        #expect(node["keep"] == .scalar("a\n\n"))
        #expect(node["dash"] == .list([.scalar("x\n")]))
        #expect(node["empty"] == .scalar(""))
        #expect(node["after"] == .scalar("1"))
        #expect(try ComposeYAML.parse("k: |+\n\nz: 1")["k"] == .scalar("\n"))
        #expect(ComposeYAML.fold(["", "a", "b"]) == "\na b")
    }

    @Test(arguments: [
        "a:\n\tb: 1", "a: 1\n---\nb: 2", "%YAML 1.2\na: 1", "a: 1\n b: 2\nc: 3", "a: 1\n  - b", "- - a",
        "a:\n  <<: *x", "a: &x 1", "a: *x", "a: !tag x", "a: @x", "a: `x", "a: %x", "a: b: c", "a: [1, 2",
        "a: {b: 1", "a: [[1]]", "a: {b}", "a: |2\n  x", "a: >\n  x\n    y", "a: |\n    x\n  y",
        "a: x\n  y", "- x\n  y", "a: \"x\" \"y\"", "just text"
    ])
    func refusals(_ text: String) {
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse(text) }
    }

    @Test func corners() throws {
        #expect(try ComposeYAML.parse("list:\n  -\n    a: 1")["list"]?.items?.first?["a"] == .scalar("1"))
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse("  a: 1\nb: 2") }
        #expect(try ComposeYAML.parse("c: [\"sh\", \"-c\", \"echo \\\"hi, there\\\"\"]")["c"]?.items?.count == 3)
    }

    @Test func keysAndQuotes() {
        #expect(ComposeYAML.key("\"a b\": c")?.0 == "a b")
        #expect(ComposeYAML.key("\"a\":c") == nil)
        #expect(ComposeYAML.key("\"a\" c") == nil)
        #expect(ComposeYAML.key("plain") == nil)
        #expect(ComposeYAML.key("[a]: b") == nil)
        #expect(ComposeYAML.key("a:")?.1 == "")
        #expect(ComposeYAML.opensQuote("") && ComposeYAML.opensQuote("[") && !ComposeYAML.opensQuote("a"))
    }
}
