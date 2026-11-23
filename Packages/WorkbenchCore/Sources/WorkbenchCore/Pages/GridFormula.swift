import Foundation

extension Grid {
    /// What a cell shows: its number, its words, or that its formula cannot be worked out.
    public enum Value: Equatable, Sendable {
        case number(Double)
        case words(String)
        case failed
    }

    /// Every cell's shown value. A formula starts with "="; cell names are A1 style, where row 1 is the first row
    /// under the header. A formula may use + - * / ( ) and SUM, AVERAGE, MIN, MAX, COUNT over cells and ranges.
    public var values: [[Value]] {
        rows.indices.map { row in
            rows[row].indices.map { column in value(at: Place(row: row, column: column), trail: []) }
        }
    }

    struct Place: Hashable {
        var row: Int
        var column: Int

        /// The place a cell name such as "B3" gives; nil when the text is not a cell name.
        init?(name: some StringProtocol) {
            let letters = name.prefix { $0.isLetter }
            guard !letters.isEmpty, let number = Int(name.dropFirst(letters.count)), number > 0 else { return nil }
            row = number - 1
            column = letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
        }

        init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    /// `trail` holds the cells whose formulas are being worked out, so a formula that reaches itself fails.
    func value(at place: Place, trail: Set<Place>) -> Value {
        guard rows.indices.contains(place.row), rows[place.row].indices.contains(place.column), !trail.contains(place)
        else { return .failed }
        let text = rows[place.row][place.column].trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("=") else {
            return Double(text.replacingOccurrences(of: ",", with: "")).map(Value.number) ?? .words(text)
        }
        var formula = GridFormula(text: text.dropFirst()) { self.value(at: $0, trail: trail.union([place])) }
        return formula.result().map(Value.number) ?? .failed
    }
}

/// One formula, read left to right. Every failure (a name that is not a cell, a cell with words, a division by zero,
/// text left over) gives nil.
struct GridFormula {
    private enum Token: Equatable {
        case number(Double)
        case cells(String)
        case function(String)
        case symbol(Character)
    }

    private static let functions: [String: @Sendable ([Double]) -> Double?] = [
        "SUM": { $0.reduce(0, +) }, "COUNT": { Double($0.count) }, "MIN": { $0.min() }, "MAX": { $0.max() },
        "AVERAGE": { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) },
    ]

    private var tokens: [Token]
    private var position = 0
    private let valueAt: (Grid.Place) -> Grid.Value

    init(text: some StringProtocol, valueAt: @escaping (Grid.Place) -> Grid.Value) {
        tokens = Self.tokens(of: text.uppercased())
        self.valueAt = valueAt
    }

    mutating func result() -> Double? {
        guard !tokens.isEmpty, let value = total(), position == tokens.count, value.isFinite else { return nil }
        return value
    }

    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var rest = Substring(text)
        while let first = rest.first {
            if first.isWhitespace {
                rest = rest.dropFirst()
            } else if first.isNumber {
                let digits = rest.prefix { $0.isNumber || $0 == "." }
                tokens.append(Double(digits).map(Token.number) ?? .symbol("?"))
                rest = rest.dropFirst(digits.count)
            } else if first.isLetter {
                let word = rest.prefix { $0.isLetter || $0.isNumber || $0 == ":" }
                tokens.append(functions[String(word)] == nil ? .cells(String(word)) : .function(String(word)))
                rest = rest.dropFirst(word.count)
            } else {
                tokens.append(.symbol(first))
                rest = rest.dropFirst()
            }
        }
        return tokens
    }

    private var next: Token? { position < tokens.count ? tokens[position] : nil }

    private mutating func take(_ symbol: Character) -> Bool {
        guard next == .symbol(symbol) else { return false }
        position += 1
        return true
    }

    private mutating func total() -> Double? {
        guard var value = product() else { return nil }
        while true {
            if take("+") {
                guard let right = product() else { return nil }
                value += right
            } else if take("-") {
                guard let right = product() else { return nil }
                value -= right
            } else {
                return value
            }
        }
    }

    private mutating func product() -> Double? {
        guard var value = factor() else { return nil }
        while true {
            if take("*") {
                guard let right = factor() else { return nil }
                value *= right
            } else if take("/") {
                guard let right = factor(), right != 0 else { return nil }
                value /= right
            } else {
                return value
            }
        }
    }

    private mutating func factor() -> Double? {
        guard let token = next else { return nil }
        position += 1
        switch token {
        case .number(let value): return value
        case .cells(let name):
            guard let place = Grid.Place(name: name), case .number(let value) = valueAt(place) else { return nil }
            return value
        case .function(let name): return take("(") ? call(name) : nil
        case .symbol("("):
            guard let value = total(), take(")") else { return nil }
            return value
        case .symbol("-"): return factor().map { -$0 }
        case .symbol: return nil
        }
    }

    /// The arguments of a function, then its value. A range gives its numbers; a cell of words in a range is left out.
    private mutating func call(_ name: String) -> Double? {
        var numbers: [Double] = []
        repeat {
            if case .cells(let range) = next, range.contains(":") {
                position += 1
                guard let found = self.numbers(in: range) else { return nil }
                numbers += found
            } else {
                guard let value = total() else { return nil }
                numbers.append(value)
            }
        } while take(",")
        guard take(")") else { return nil }
        return Self.functions[name]?(numbers)
    }

    private func numbers(in range: String) -> [Double]? {
        let ends = range.split(separator: ":").compactMap { Grid.Place(name: $0) }
        guard ends.count == 2 else { return nil }
        var numbers: [Double] = []
        for row in min(ends[0].row, ends[1].row)...max(ends[0].row, ends[1].row) {
            for column in min(ends[0].column, ends[1].column)...max(ends[0].column, ends[1].column) {
                switch valueAt(Grid.Place(row: row, column: column)) {
                case .number(let value): numbers.append(value)
                case .words: continue
                case .failed: return nil
                }
            }
        }
        return numbers
    }
}
