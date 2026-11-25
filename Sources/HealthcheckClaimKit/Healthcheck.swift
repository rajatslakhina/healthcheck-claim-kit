/// A healthcheck as the Docker engine stores it (`docker inspect .Config.Healthcheck`): the test and the timings,
/// where `nil` and `0` mean "not set" and the engine falls back to the image's value, then to its own default.
public struct Healthcheck: Sendable, Hashable {
    /// `["CMD", ...]`, `["CMD-SHELL", script]` or `["NONE"]`; `nil` when not set.
    public var test: [String]?
    /// Nanoseconds.
    public var interval: Int64 = 0
    public var timeout: Int64 = 0
    public var startPeriod: Int64 = 0
    public var startInterval: Int64 = 0
    public var retries = 0

    public init(test: [String]? = nil, interval: Int64 = 0, timeout: Int64 = 0, startPeriod: Int64 = 0,
                startInterval: Int64 = 0, retries: Int = 0) {
        self.test = test
        self.interval = interval
        self.timeout = timeout
        self.startPeriod = startPeriod
        self.startInterval = startInterval
        self.retries = retries
    }

    /// The engine's defaults (moby `daemon/health.go`): a field left at zero runs with these.
    public enum Defaults {
        public static let interval: Int64 = 30_000_000_000
        public static let timeout: Int64 = 30_000_000_000
        public static let startPeriod: Int64 = 0
        public static let startInterval: Int64 = 5_000_000_000
        public static let retries = 3
    }

    /// This compose healthcheck over the image's, the way the engine merges them when it creates the container:
    /// every field left unset (an empty `test`, a zero timing, `retries` 0) takes the image's value.
    public func merged(over image: Healthcheck?) -> Healthcheck {
        guard let image else { return self }
        var merged = self
        if merged.test?.isEmpty ?? true { merged.test = image.test }
        if merged.interval == 0 { merged.interval = image.interval }
        if merged.timeout == 0 { merged.timeout = image.timeout }
        if merged.startPeriod == 0 { merged.startPeriod = image.startPeriod }
        if merged.startInterval == 0 { merged.startInterval = image.startInterval }
        if merged.retries == 0 { merged.retries = image.retries }
        return merged
    }

    /// No check runs: no test at all, or `NONE`.
    public var isDisabled: Bool {
        test?.first.map { $0 == "NONE" } ?? true
    }

    /// The test runs through `/bin/sh -c` (`CMD-SHELL`, which is what a string `test:` becomes).
    public var runsInShell: Bool {
        test?.first == "CMD-SHELL"
    }

    public var effectiveInterval: Int64 { interval == 0 ? Defaults.interval : interval }
    public var effectiveTimeout: Int64 { timeout == 0 ? Defaults.timeout : timeout }
    public var effectiveStartPeriod: Int64 { startPeriod == 0 ? Defaults.startPeriod : startPeriod }
    public var effectiveStartInterval: Int64 { startInterval == 0 ? Defaults.startInterval : startInterval }
    public var effectiveRetries: Int { retries <= 0 ? Defaults.retries : retries }

    /// The settings in the engine's units, the way `docker compose config` prints them.
    public var summary: String {
        let test = (test ?? []).map { "\"\($0)\"" }.joined(separator: ", ")
        return "test [\(test)], interval \(GoDuration.format(effectiveInterval)), "
            + "timeout \(GoDuration.format(effectiveTimeout)), retries \(effectiveRetries), "
            + "start_period \(GoDuration.format(effectiveStartPeriod)), "
            + "start_interval \(GoDuration.format(effectiveStartInterval))"
    }
}

/// The settings a healthcheck can have, as compose names them.
public enum HealthSetting: String, Sendable, Hashable, CaseIterable {
    case interval
    case timeout
    case retries
    case startPeriod = "start_period"
    case startInterval = "start_interval"

    /// The engine's default, in nanoseconds for timings and as a count for `retries`.
    public var defaultValue: Int64 {
        switch self {
        case .interval: Healthcheck.Defaults.interval
        case .timeout: Healthcheck.Defaults.timeout
        case .retries: Int64(Healthcheck.Defaults.retries)
        case .startPeriod: Healthcheck.Defaults.startPeriod
        case .startInterval: Healthcheck.Defaults.startInterval
        }
    }

    public var isDuration: Bool {
        self != .retries
    }

    /// The Dockerfile `HEALTHCHECK` option for this setting.
    var flag: String {
        "--" + rawValue.replacingOccurrences(of: "_", with: "-")
    }

    /// The value written for people: `30s`, `3`.
    func written(_ value: Int64) -> String {
        isDuration ? GoDuration.format(value) : "\(value)"
    }
}
