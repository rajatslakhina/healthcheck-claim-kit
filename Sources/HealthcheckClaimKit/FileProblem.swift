/// Something in a compose file's or Dockerfile's healthcheck that does not do what it looks like.
public enum FileProblem: String, Sendable, Hashable, CaseIterable {
    /// A `test:` list that does not start with `CMD`, `CMD-SHELL` or `NONE`: compose refuses the file.
    case unknownTestType
    /// `test:` with no value: compose refuses the file ("must be a string").
    case testWithoutValue
    /// A timing written as a bare number (`interval: 30`): compose refuses the file.
    case durationNeedsUnit
    /// A timing Go cannot read (`1d`, `1m 30s`, `90S`): compose refuses the file.
    case durationRefused
    /// A timing below 1ms (or negative): the engine refuses to create the container.
    case durationTooShort
    /// A negative `retries`: compose refuses the file.
    case retriesNegative
    /// A shell operator (`||`, `&&`, `|`, `;`, `>`) as an item of the exec form: it reaches the program as an argument.
    case operatorInExecForm
    /// `["CMD-SHELL", "curl", "-f", "url"]`: the shell runs the first string only; the rest become `$0`, `$1`.
    case scriptInPieces
    /// A variable in the exec form (`$$NAME` in compose, `$NAME` in a Dockerfile): no shell expands it, so the
    /// program gets the text `$NAME`.
    case variableInExecForm
    /// `$NAME` in `test:` set only in the service's `environment:`: compose substitutes it from the shell and `.env`
    /// when it reads the file, so the check gets an empty string (or the shell's value).
    case containerVariable
    /// The test calls `localhost` on the published host port; inside the container the app listens on the target port.
    case publishedPortInTest
    /// `retries: 0` is the same as not setting it: the image's value or 3.
    case retriesZero
    /// `disable: true` next to a `test:`: the test never runs.
    case disableWithTest

    /// Compose or the engine stops on this file before any check runs.
    public var isRefused: Bool {
        [.unknownTestType, .testWithoutValue, .durationNeedsUnit, .durationRefused, .durationTooShort,
         .retriesNegative].contains(self)
    }

    /// Wrong as written, not only worth a second look.
    public var isWrong: Bool {
        isRefused || [.operatorInExecForm, .scriptInPieces, .variableInExecForm].contains(self)
    }
}

/// One file problem and where it is.
public struct FileFinding: Sendable, Hashable {
    public let problem: FileProblem
    /// The service (empty for a healthcheck shown on its own, or a Dockerfile).
    public let service: String
    /// The line of the file the problem is on.
    public let line: Int
    /// The text the problem is about: the item, the value, the variable name, the port.
    public let detail: String
    /// The source line, for telling a line the question showed from one the answer wrote.
    let source: String

    public init(problem: FileProblem, service: String, line: Int, detail: String) {
        self.init(problem: problem, service: service, line: line, detail: detail, source: "")
    }

    init(problem: FileProblem, service: String, line: Int, detail: String, source: String) {
        self.problem = problem
        self.service = service
        self.line = line
        self.detail = detail
        self.source = source
    }
}
