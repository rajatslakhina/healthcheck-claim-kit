/// A compose service as far as its healthcheck goes.
public struct HealthService: Sendable, Hashable {
    public let name: String
    /// The `image:` it runs, if any.
    public internal(set) var image: String?
    /// It has `build:`, so its image comes from a Dockerfile.
    public internal(set) var builds = false
    /// The `healthcheck:` as compose hands it to the engine; `nil` when the service has none or it is refused.
    public internal(set) var healthcheck: Healthcheck?
    /// The service writes a `healthcheck:` key.
    public internal(set) var hasHealthcheckKey = false
    /// Problems in this service's healthcheck lines.
    public internal(set) var problems: [FileFinding] = []
    /// `environment:` as written: each name and its value (`nil` for `- NAME` or `NAME:` with none).
    var environment: [String: String?] = [:]
    /// Published host ports and the container ports they reach.
    var ports: [PortPair] = []

    init(name: String) {
        self.name = name
    }

    /// The healthcheck the container gets: this one over the image's. With the image's unknown, `nil`, because an
    /// unseen `HEALTHCHECK` fills every field compose leaves unset; only a check compose disables is settled.
    public func effective(image imageHealthcheck: ImageHealth) -> Healthcheck? {
        guard case let .known(image) = imageHealthcheck else {
            return healthcheck?.test?.first == "NONE" ? healthcheck : nil
        }
        guard let healthcheck else { return image }
        return healthcheck.merged(over: image)
    }
}

/// What a compose file's services do about healthchecks.
public struct HealthProject: Sendable, Hashable {
    public let services: [HealthService]

    public func service(_ name: String) -> HealthService? {
        services.first { $0.name == name }
    }

    /// Every problem in the file, in file order.
    public var problems: [FileFinding] {
        services.flatMap(\.problems).enumerated().sorted { ($0.element.line, $0.offset) < ($1.element.line, $1.offset) }
            .map(\.element)
    }

    enum Reading: Hashable {
        case project(HealthProject)
        /// YAML this reader does not follow.
        case unfollowed(String)
        /// Not a compose file or healthcheck fragment.
        case none
    }

    static func read(_ text: String, variables: Variables) -> Reading {
        let root: ComposeNode
        do {
            root = try ComposeYAML.parse(text)
        } catch {
            return .unfollowed(error.reason)
        }
        let lines = text.components(separatedBy: "\n")
        if let services = root["services"]?.entries {
            return .project(HealthProject(services: services.map {
                HealthServiceReader(variables: variables, lines: lines).read($0.key, $0.value)
            }))
        }
        if root["healthcheck"] != nil {
            return .project(HealthProject(services: [
                HealthServiceReader(variables: variables, lines: lines).read("", root)
            ]))
        }
        return .none
    }

    /// Whether a code block is a compose file or a healthcheck fragment.
    static func looksLikeHealthYAML(_ text: String) -> Bool {
        let keys = text.components(separatedBy: "\n").map(\.trimmed)
        return keys.contains { $0.hasPrefix("services:") || $0.hasPrefix("healthcheck:") }
    }
}

/// Reads one service.
struct HealthServiceReader {
    let variables: Variables
    let lines: [String]

    func read(_ name: String, _ node: ComposeNode) -> HealthService {
        var service = HealthService(name: name)
        service.image = node["image"]?.text
        service.builds = node["build"] != nil
        service.environment = Self.environmentNames(node["environment"])
        service.ports = node["ports"]?.items?.compactMap(Self.port) ?? []
        if let entry = node.entry("healthcheck") {
            service.hasHealthcheckKey = true
            var reader = HealthcheckReader(service: name, variables: variables, lines: lines)
            service.healthcheck = reader.read(entry.value)
            service.problems = reader.problems
                + FileChecks.lineProblems(entry.value, service: service, variables: variables, lines: lines)
            if service.problems.contains(where: \.problem.isRefused) { service.healthcheck = nil }
        }
        return service
    }

    static func environmentNames(_ node: ComposeNode?) -> [String: String?] {
        var values: [String: String?] = [:]
        for entry in node?.entries ?? [] { values[entry.key] = entry.value.text }
        for item in node?.items?.compactMap(\.text) ?? [] {
            let name = String(item.prefix { $0 != "=" }).trimmed
            values[name] = item.contains("=") ? String(item.drop { $0 != "=" }.dropFirst()) : String?.none
        }
        return values
    }

    /// `"8080:80"`, `"127.0.0.1:8080:80/tcp"`, or `{target: 80, published: 8080}`.
    static func port(_ node: ComposeNode) -> PortPair? {
        if let entries = node.entries {
            let target = entries.last { $0.key == "target" }?.value.text.flatMap { Int($0) }
            let published = entries.last { $0.key == "published" }?.value.text.flatMap { Int($0) }
            guard let target, let published else { return nil }
            return PortPair(published: published, target: target)
        }
        guard let text = node.text else { return nil }
        let parts = text.split(separator: "/")[0].split(separator: ":")
        guard parts.count >= 2, let target = Int(parts[parts.count - 1]), let published = Int(parts[parts.count - 2])
        else { return nil }
        return PortPair(published: published, target: target)
    }
}

/// A published host port and the container port it reaches.
struct PortPair: Sendable, Hashable {
    let published: Int
    let target: Int
}
