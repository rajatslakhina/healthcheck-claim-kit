/// A YAML value as far as a compose file needs one: scalars stay text, the way compose reads them.
public indirect enum ComposeNode: Sendable, Hashable {
    case null
    case scalar(String)
    case list([ComposeNode])
    case map([ComposeEntry])

    /// The value under a key of a mapping; the last one when a key repeats.
    public subscript(key: String) -> ComposeNode? {
        entry(key)?.value
    }

    /// The entry for a key of a mapping; the last one when a key repeats.
    public func entry(_ key: String) -> ComposeEntry? {
        entries?.last { $0.key == key }
    }

    public var text: String? {
        if case let .scalar(text) = self { return text }
        return nil
    }

    public var items: [ComposeNode]? {
        if case let .list(items) = self { return items }
        return nil
    }

    public var entries: [ComposeEntry]? {
        if case let .map(entries) = self { return entries }
        return nil
    }
}

public struct ComposeEntry: Sendable, Hashable {
    public let key: String
    public let value: ComposeNode
    /// The line of the file the key is on.
    public let line: Int

    public init(key: String, value: ComposeNode, line: Int) {
        self.key = key
        self.value = value
        self.line = line
    }
}
