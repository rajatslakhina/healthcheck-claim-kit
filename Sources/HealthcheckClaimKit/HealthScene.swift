/// What the conversation shows that decides how its healthchecks behave: the compose file, the Dockerfile its
/// `build:` services use, the variables compose substitutes, and whether a healthcheck is in view at all.
public struct HealthScene: Sendable, Hashable {
    /// The last compose file (or healthcheck fragment) shown.
    public internal(set) var project: HealthProject?
    /// The healthcheck of the image the last Dockerfile shown builds.
    public internal(set) var image: ImageHealth = .unknown
    public internal(set) var variables = Variables()
    /// The conversation shows a compose `healthcheck:` or a Dockerfile `HEALTHCHECK`.
    public internal(set) var showsHealthcheck = false
    /// The conversation is about Docker at all.
    public internal(set) var aboutDocker = false
    /// The forms (`CMD`, `CMD-SHELL`) the healthcheck tests in view are written in.
    var testForms: Set<String> = []
    /// Problems in the healthcheck lines of the answer's own last compose file and Dockerfile, without lines the
    /// question already showed (an answer quotes the broken file to explain it).
    var answerProblems: [FileFinding] = []

    public init() {}

    /// The healthcheck a service's container gets, when the conversation shows enough to say.
    public func effective(_ name: String) -> Healthcheck? {
        guard let service = project?.service(name) else { return nil }
        return service.effective(image: service.builds ? image : .unknown)
    }
}

enum BlockKind: Equatable {
    case compose
    case dockerfile
    case env
    case shell
    case other
    case prose
}

enum SceneReader {
    static func kind(of block: AnswerBlock, after prose: String) -> BlockKind {
        guard case let .code(info) = block.kind else { return .prose }
        let topLevel = block.lines.filter { $0.first.map { !$0.isWhitespace } == true }
        let foreign = ["apiVersion:", "kind:", "jobs:", "on:", "steps:"]
        if topLevel.contains(where: { line in foreign.contains { line.hasPrefix($0) } }) { return .other }
        let tag = String(info.prefix { !" :{".contains($0) })
        if ["dockerfile", "containerfile"].contains(tag) || looksLikeDockerfile(block.lines) { return .dockerfile }
        if HealthProject.looksLikeHealthYAML(block.text) { return .compose }
        if ["env", "dotenv"].contains(tag) || info.contains(".env")
            || (EnvFile.looksLikeEnvFile(block.lines) && prose.contains(".env")) {
            return .env
        }
        return .shell
    }

    static func looksLikeDockerfile(_ lines: [String]) -> Bool {
        let instructions = lines.map(\.trimmed).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return instructions.first?.uppercased().hasPrefix("FROM ") == true
            || instructions.contains { $0.hasPrefix("HEALTHCHECK ") }
    }

    static func classify(_ text: String) -> [(block: AnswerBlock, kind: BlockKind)] {
        var previous = ""
        return AnswerBlocks.split(text).map { block in
            let kind = kind(of: block, after: previous)
            if kind == .prose { previous = block.lines.last { !$0.trimmed.isEmpty }?.folded ?? "" }
            return (block, kind)
        }
    }

    static func read(answer: String, context: String, earlier: HealthScene?) -> HealthScene {
        let answerBlocks = classify(answer)
        let contextBlocks = classify(context)
        var scene = HealthScene()
        scene.variables = variables(contextBlocks + answerBlocks, earlier: earlier?.variables ?? Variables())
        let projects = { (blocks: [(block: AnswerBlock, kind: BlockKind)]) -> [HealthProject] in
            blocks.filter { $0.kind == .compose }.compactMap { block in
                if case let .project(project) = HealthProject.read(block.block.text, variables: scene.variables) {
                    return project
                }
                return nil
            }
        }
        let dockerfiles = { (blocks: [(block: AnswerBlock, kind: BlockKind)]) -> [DockerfileHealth] in
            blocks.filter { $0.kind == .dockerfile }.map { DockerfileHealth.read($0.block.text) }
        }
        let answerProjects = projects(answerBlocks)
        let answerDockerfiles = dockerfiles(answerBlocks)
        let shownProjects = projects(contextBlocks) + answerProjects
        let shownDockerfiles = dockerfiles(contextBlocks) + answerDockerfiles
        scene.project = shownProjects.last ?? earlier?.project
        scene.image = shownDockerfiles.last?.image ?? earlier?.image ?? .unknown
        scene.showsHealthcheck = earlier?.showsHealthcheck == true
            || shownProjects.contains { $0.services.contains(where: \.hasHealthcheckKey) }
            || shownDockerfiles.contains(where: \.hasHealthcheck)
        let tests = shownProjects.flatMap(\.services).compactMap { $0.healthcheck?.test?.first }
            + shownDockerfiles.compactMap { dockerfile in
                if case let .known(check) = dockerfile.image { return check?.test?.first }
                return nil
            }
        scene.testForms = (earlier?.testForms ?? []).union(tests.filter { $0 == "CMD" || $0 == "CMD-SHELL" })
        let quoted = Set(contextBlocks.filter { $0.kind != .prose }.flatMap(\.block.lines).map(\.trimmed))
        let problems = (answerProjects.last?.problems ?? []) + (answerDockerfiles.last?.problems ?? [])
        scene.answerProblems = problems.filter { !quoted.contains($0.source) }
        let folded = (answer + "\n" + context).folded
        scene.aboutDocker = earlier?.aboutDocker == true || scene.showsHealthcheck || !shownProjects.isEmpty
            || Words.containsAny(folded, ["docker", "compose", "container", "containers", "dockerfile", "healthcheck",
                                          "healthchecks", "start_period", "start_interval", "cmd-shell"])
        return scene
    }

    static func variables(_ blocks: [(block: AnswerBlock, kind: BlockKind)], earlier: Variables) -> Variables {
        var variables = earlier
        for (block, kind) in blocks {
            if kind == .env {
                for (name, value) in EnvFile.parse(block.lines) { variables.dotEnv[name] = value }
            } else if kind == .shell {
                let exports = block.lines.map(\.trimmed).filter { $0.hasPrefix("export ") }
                for (name, value) in EnvFile.parse(exports) { variables.shell[name] = value }
            }
        }
        return variables
    }
}
