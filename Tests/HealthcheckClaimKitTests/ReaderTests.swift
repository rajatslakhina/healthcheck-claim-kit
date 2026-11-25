@testable import HealthcheckClaimKit
import Testing

@Suite("Reading compose files and Dockerfiles")
struct ReaderTests {
    func project(_ text: String, _ variables: Variables = Variables()) -> HealthProject? {
        if case let .project(project) = HealthProject.read(text, variables: variables) { return project }
        return nil
    }

    @Test func servicesFragmentsAndOthers() throws {
        let file = try #require(project("""
        services:
          web:
            image: nginx
            ports:
              - "8080:80"
              - "127.0.0.1:9000:9001/tcp"
              - "443"
              - {target: 5432, published: 5433}
              - {target: 1}
            environment: [A=1, B]
            healthcheck:
              test: ["CMD", "true"]
          api:
            build: .
            environment: {C: x}
        """))
        let web = try #require(file.service("web"))
        #expect(web.image == "nginx" && !web.builds && web.hasHealthcheckKey)
        #expect(web.ports == [PortPair(published: 8080, target: 80), PortPair(published: 9000, target: 9001),
                              PortPair(published: 5433, target: 5432)])
        #expect(web.environment == ["A": "1", "B": String?.none])
        let api = try #require(file.service("api"))
        #expect(api.builds && !api.hasHealthcheckKey && api.environment == ["C": "x"] && api.healthcheck == nil)
        #expect(file.service("none") == nil)
        let fragment = try #require(project("    healthcheck:\n      test: curl -f x\n"))
        #expect(fragment.services.map(\.name) == [""])
        #expect(fragment.services[0].healthcheck?.test == ["CMD-SHELL", "curl -f x"])
        #expect(HealthProject.read("a: 1", variables: Variables()) == .none)
        #expect(HealthProject.read("a: &x 1", variables: Variables()) == .unfollowed("an anchor (line 1)"))
        #expect(HealthProject.looksLikeHealthYAML("x:\n  healthcheck:") && !HealthProject.looksLikeHealthYAML("a: 1"))
    }

    @Test func unfollowedValuesStayUnset() throws {
        let file = try #require(project("""
        services:
          web:
            healthcheck:
              test:
                - CMD
                - a: 1
              interval: [1s]
              retries: many
              disable: yes
        """))
        let check = try #require(file.service("web")?.healthcheck)
        #expect(check == Healthcheck())
        let malformed = try #require(project("services:\n  web:\n    healthcheck:\n      test: ${A\n"))
        #expect(malformed.service("web")?.healthcheck?.test == nil)
        let mapped = try #require(project("services:\n  web:\n    healthcheck:\n      test: {a: 1}\n"))
        #expect(mapped.service("web")?.healthcheck?.test == nil)
        let notMap = try #require(project("services:\n  web:\n    healthcheck: x\n"))
        #expect(notMap.service("web")?.healthcheck == Healthcheck())
    }

    @Test func refusalsBlankTheHealthcheck() throws {
        let file = try #require(project("""
        services:
          web:
            healthcheck:
              test: ["CMD", "true"]
              retries: -2
              timeout: 0.5ms
        """))
        let web = try #require(file.service("web"))
        #expect(web.healthcheck == nil)
        #expect(web.problems.map(\.problem) == [.retriesNegative, .durationTooShort])
        #expect(file.problems.map(\.line) == [5, 6])
        #expect(web.problems[0].source == "retries: -2")
        #expect(HealthcheckReader.line(99, in: ["a"]).isEmpty)
    }

    @Test func dockerfileStagesAndOptions() {
        let options = DockerfileHealth.read("FROM scratch\nHEALTHCHECK --interval=5s --timeout=1s --start-period=2s "
                                            + "--start-interval=1s --retries=4 CMD [\"x\"]")
        #expect(options.image == .known(Healthcheck(test: ["CMD", "x"], interval: 5_000_000_000,
                                                     timeout: 1_000_000_000, startPeriod: 2_000_000_000,
                                                     startInterval: 1_000_000_000, retries: 4)))
        #expect(options.hasHealthcheck)
        #expect(DockerfileHealth.read("FROM node:22\nRUN x").image == .unknown)
        #expect(DockerfileHealth.read("FROM --platform=linux/amd64 scratch").image == .known(nil))
        #expect(DockerfileHealth.read("FROM").image == .unknown)
        #expect(DockerfileHealth.read("# escape=`\nFROM scratch\nHEALTHCHECK NONE").image == .unknown)
        #expect(DockerfileHealth.read("FROM scratch\nHEALTHCHECK CMD").image == .unknown)
        #expect(DockerfileHealth.read("FROM scratch\nHEALTHCHECK --retries=x CMD y").image == .unknown)
        #expect(DockerfileHealth.read("FROM scratch\nHEALTHCHECK --interval CMD y").image == .unknown)
        let joined = DockerfileHealth.logicalLines("A \\\n\n# c\nB \\")
        #expect(joined.count == 1 && joined[0].number == 1 && joined[0].text.hasSuffix("B"))
    }

    @Test func dockerfileProblems() {
        let read = DockerfileHealth.read("""
        FROM scratch
        HEALTHCHECK CMD ["curl", "-f", "$URL", "||", "exit", "1"]
        HEALTHCHECK CMD ["sh", "-c", "curl $URL"]
        HEALTHCHECK CMD curl $URL || exit 1
        """)
        #expect(read.problems.map(\.problem) == [.operatorInExecForm, .variableInExecForm])
        #expect(read.problems.map(\.line) == [2, 2])
        #expect(read.problems[1].detail == "$URL")
    }
}
