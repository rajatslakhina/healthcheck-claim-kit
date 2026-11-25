/// Durations the way Go's `time.ParseDuration` reads them, which is what compose and `docker build` use for
/// `interval`, `timeout`, `start_period` and `start_interval`: `10s`, `1m30s`, `1.5s`, `500ms`, `100us`. A space, a
/// capital unit or a unit such as `d` is refused. Values are nanoseconds.
enum GoDuration {
    enum Failure: Error, Equatable {
        case invalid
        case missingUnit
        case unknownUnit(String)
    }

    static let units: [String: Int64] = [
        "ns": 1, "us": 1_000, "\u{00B5}s": 1_000, "\u{03BC}s": 1_000, "ms": 1_000_000, "s": 1_000_000_000,
        "m": 60_000_000_000, "h": 3_600_000_000_000
    ]

    static func parse(_ text: String) throws(Failure) -> Int64 {
        var rest = Substring(text)
        var negative = false
        if let sign = rest.first, sign == "-" || sign == "+" {
            negative = sign == "-"
            rest = rest.dropFirst()
        }
        if rest == "0" { return 0 }
        guard !rest.isEmpty else { throw .invalid }
        var total: Int64 = 0
        while !rest.isEmpty {
            total = try add(total, segment(&rest))
        }
        return negative ? -total : total
    }

    /// One `<number><unit>` piece from the front of the text.
    static func segment(_ rest: inout Substring) throws(Failure) -> Int64 {
        let whole = rest.prefix(while: \.isASCIIDigit)
        rest = rest.dropFirst(whole.count)
        var fraction: Substring = ""
        var hasPoint = false
        if rest.first == "." {
            hasPoint = true
            rest = rest.dropFirst()
            fraction = rest.prefix(while: \.isASCIIDigit)
            rest = rest.dropFirst(fraction.count)
        }
        guard !whole.isEmpty || (hasPoint && !fraction.isEmpty) else { throw .invalid }
        let unitText = rest.prefix { $0 != "." && !$0.isASCIIDigit }
        rest = rest.dropFirst(unitText.count)
        guard !unitText.isEmpty else { throw .missingUnit }
        guard let unit = units[String(unitText)] else { throw .unknownUnit(String(unitText)) }
        let wholeValue = try multiply(Int64(whole) ?? 0, unit)
        return try add(wholeValue, fractionValue(fraction, unit))
    }

    static func fractionValue(_ digits: Substring, _ unit: Int64) throws(Failure) -> Int64 {
        var value: Int64 = 0
        var scale: Int64 = 1
        // Go stops reading fraction digits once more would overflow; nine are enough for a nanosecond.
        for digit in digits.utf8.prefix(18) {
            value = value * 10 + Int64(digit - UInt8(ascii: "0"))
            scale *= 10
        }
        let (product, overflow) = value.multipliedReportingOverflow(by: unit)
        guard !overflow else { throw .invalid }
        return product / scale
    }

    static func multiply(_ lhs: Int64, _ rhs: Int64) throws(Failure) -> Int64 {
        let (product, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else { throw .invalid }
        return product
    }

    static func add(_ lhs: Int64, _ rhs: Int64) throws(Failure) -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw .invalid }
        return sum
    }

    /// The duration written the way Go prints it (and `docker compose config` shows it): `1m30s`, `1h0m0s`, `500ms`.
    static func format(_ value: Int64) -> String {
        if value == 0 { return "0s" }
        let magnitude = value.magnitude
        var text: String
        if magnitude < 1_000_000_000 {
            let (unit, scale): (String, UInt64) = magnitude < 1_000 ? ("ns", 1)
                : magnitude < 1_000_000 ? ("\u{00B5}s", 1_000) : ("ms", 1_000_000)
            text = decimal(magnitude, scale) + unit
        } else {
            let hours = magnitude / 3_600_000_000_000
            let minutes = magnitude % 3_600_000_000_000 / 60_000_000_000
            text = decimal(magnitude % 60_000_000_000, 1_000_000_000) + "s"
            if hours > 0 || minutes > 0 { text = "\(minutes)m" + text }
            if hours > 0 { text = "\(hours)h" + text }
        }
        return value < 0 ? "-" + text : text
    }

    /// `value / scale` with its fraction, trailing zeros dropped.
    static func decimal(_ value: UInt64, _ scale: UInt64) -> String {
        let whole = value / scale
        let remainder = value % scale
        guard remainder > 0 else { return "\(whole)" }
        let width = String(scale).count - 1
        var digits = String(remainder)
        digits = String(repeating: "0", count: width - digits.count) + digits
        while digits.last == "0" { digits.removeLast() }
        return "\(whole).\(digits)"
    }
}

extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
