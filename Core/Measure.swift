import Foundation

// MARK: - Measurement expressions
//
// Every length field in the app accepts the same input:
//   1.75   1 3/4   1-3/4   3/4   7'   7' 4 1/2"   7'-4"   (3 + 1/2) × 2   19 mm   14 cm   2.4 m
// The result is in the parser's default unit (inches or millimeters). A bare number is in the
// default unit; a suffix (' " mm cm m in ft) converts that one quantity into the default unit.
//
// Rules:
//   • A space or a tight dash between a whole number and a fraction makes a mixed number:
//     "1 3/4" and "1-3/4" are both 1.75. Put spaces around a minus to subtract: "4 - 1/2".
//   • ' means feet, " means inches. A feet value followed by a number adds inches: 3' 4" = 40.
//     "3'-4" is also 40 (carpenter notation).
//   • × or * multiplies, ÷ divides, / is a fraction bar that also divides.

enum MeasureError: Error, Equatable {
    case empty
    case unexpected(Character)
    case unexpectedEnd
    case divideByZero
    case missingOperator
}

struct MeasureParser {
    enum Unit {
        case inch
        case millimeter

        /// Default units in one inch.
        var perInch: Double { self == .inch ? 1 : 25.4 }
    }

    private let chars: [Character]
    private var i = 0
    private let perInch: Double
    private var perMM: Double { perInch / 25.4 }

    private init(_ text: String, unit: Unit) {
        chars = Array(text)
        perInch = unit.perInch
    }

    /// Returns the value in `unit`, or nil if the text is empty or not a valid expression.
    static func value(_ text: String, unit: Unit = .inch) -> Double? {
        try? evaluate(text, unit: unit)
    }

    static func evaluate(_ text: String, unit: Unit = .inch) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw MeasureError.empty }
        var p = MeasureParser(normalize(trimmed), unit: unit)
        let v = try p.parseExpression()
        p.skipSpaces()
        if p.i < p.chars.count {
            let c = p.chars[p.i]
            if c.isNumber || c == "." || c == "(" { throw MeasureError.missingOperator }
            throw MeasureError.unexpected(c)
        }
        if !v.isFinite { throw MeasureError.divideByZero }
        return v
    }

    /// Maps typographic characters iOS keyboards insert to plain ones.
    private static func normalize(_ s: String) -> String {
        var out = ""
        for c in s {
            switch c {
            case "\u{2019}", "\u{2018}", "\u{2032}", "`": out.append("'")       // smart quote, prime
            case "\u{201C}", "\u{201D}", "\u{2033}": out.append("\"")           // smart double quote, double prime
            case "\u{2212}", "\u{2013}", "\u{2014}": out.append("-")            // minus sign, en and em dash
            case "*", "x", "X": out.append("×")
            case ",": out.append(".")
            case "\u{00A0}": out.append(" ")
            default: out.append(c)
            }
        }
        return out
    }

    // expression := term (('+' | '-') term)*
    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while true {
            skipSpaces()
            guard let c = peek() else { return value }
            if c == "+" {
                i += 1
                value += try parseTerm()
            } else if c == "-" {
                i += 1
                value -= try parseTerm()
            } else {
                return value
            }
        }
    }

    // term := factor (('×' | '÷' | '/') factor)*
    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()
        while true {
            skipSpaces()
            guard let c = peek() else { return value }
            if c == "×" {
                i += 1
                value *= try parseFactor()
            } else if c == "÷" || c == "/" {
                i += 1
                let d = try parseFactor()
                if d == 0 { throw MeasureError.divideByZero }
                value /= d
            } else {
                return value
            }
        }
    }

    // factor := '-' factor | '+' factor | '(' expression ')' [unit] | length
    private mutating func parseFactor() throws -> Double {
        skipSpaces()
        guard let c = peek() else { throw MeasureError.unexpectedEnd }
        if c == "-" { i += 1; return -(try parseFactor()) }
        if c == "+" { i += 1; return try parseFactor() }
        if c == "(" {
            i += 1
            let v = try parseExpression()
            skipSpaces()
            guard peek() == ")" else {
                if let ch = peek() { throw MeasureError.unexpected(ch) }
                throw MeasureError.unexpectedEnd
            }
            i += 1
            // Allow a unit after a group: (2 + 1)' = 36"
            let save = i
            skipSpaces()
            if peek() == "'" { i += 1; return v * 12 * perInch }
            if peek() == "\"" { i += 1; return v * perInch }
            if let f = parseUnitWord() { return v * f }
            i = save
            return v
        }
        if c.isNumber || c == "." { return try parseLength() }
        throw MeasureError.unexpected(c)
    }

    // length := quantity [ "'" [ ['-'] quantity ['"'] ] ] | quantity '"' | quantity unitword
    private mutating func parseLength() throws -> Double {
        let q = try parseQuantity()
        let save = i
        skipSpaces()
        if peek() == "\"" { i += 1; return q * perInch }
        if let f = parseUnitWord() { return q * f }
        if peek() == "'" {
            i += 1
            var total = q * 12
            let afterFeet = i
            // Carpenter notation 3'-4": a dash right after the feet mark, then a digit.
            if peek() == "-", let n = peek(1), n.isNumber || n == "." {
                i += 1
                total += try parseQuantity()
                skipSpaces()
                if peek() == "\"" { i += 1 }
                return total * perInch
            }
            skipSpaces()
            if let n = peek(), n.isNumber || n == "." {
                total += try parseQuantity()
                skipSpaces()
                if peek() == "\"" { i += 1 }
                return total * perInch
            }
            i = afterFeet
            return total * perInch
        }
        i = save
        return q
    }

    // quantity := number | number '/' number | int (' '+ | '-') int '/' int
    private mutating func parseQuantity() throws -> Double {
        let (whole, wholeIsInt) = try parseNumber()

        // Tight fraction: 3/4
        if peek() == "/" , let n = peek(1), n.isNumber {
            i += 1
            let (den, _) = try parseNumber()
            if den == 0 { throw MeasureError.divideByZero }
            return whole / den
        }

        // Mixed number: "1 3/4" or "1-3/4"
        if wholeIsInt {
            let save = i
            var sawSeparator = false
            if peek() == "-" {
                i += 1
                sawSeparator = true
            } else {
                while peek() == " " { i += 1; sawSeparator = true }
            }
            if sawSeparator, let n = peek(), n.isNumber {
                let start = i
                if let (num, numIsInt) = try? parseNumber(), numIsInt, peek() == "/",
                   let d = peek(1), d.isNumber {
                    i += 1
                    let (den, _) = try parseNumber()
                    if den == 0 { throw MeasureError.divideByZero }
                    return whole + num / den
                }
                i = start
            }
            i = save
        }
        return whole
    }

    private mutating func parseNumber() throws -> (Double, Bool) {
        let start = i
        var sawDot = false
        while let c = peek(), c.isNumber || (c == "." && !sawDot) {
            if c == "." { sawDot = true }
            i += 1
        }
        let text = String(chars[start..<i])
        guard !text.isEmpty, text != ".", let v = Double(text) else {
            if let c = peek() { throw MeasureError.unexpected(c) }
            throw MeasureError.unexpectedEnd
        }
        return (v, !sawDot)
    }

    /// Reads mm, cm, m, in or ft at the cursor and returns the factor into the default unit.
    /// Leaves the cursor alone and returns nil if the letters there are not one of those words.
    private mutating func parseUnitWord() -> Double? {
        let start = i
        var word = ""
        while let c = peek(), c.isLetter {
            word.append(Character(c.lowercased()))
            i += 1
        }
        switch word {
        case "mm": return perMM
        case "cm": return 10 * perMM
        case "m": return 1000 * perMM
        case "in": return perInch
        case "ft": return 12 * perInch
        default:
            i = start
            return nil
        }
    }

    private func peek(_ offset: Int = 0) -> Character? {
        let j = i + offset
        return j < chars.count ? chars[j] : nil
    }

    private mutating func skipSpaces() {
        while let c = peek(), c == " " || c == "\t" { i += 1 }
    }
}

// MARK: - Formatting

enum Format {
    /// Nearest fraction of an inch, reduced. 2.2866 at 32 → "2 9/32".
    static func fraction(_ inches: Double, denominator: Int) -> String {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return decimal(inches, places: 3) }
        let negative = inches < 0
        let units = Int((abs(inches) * Double(denominator)).rounded())
        let whole = units / denominator
        var num = units % denominator
        var den = denominator
        if num == 0 {
            return (negative && whole != 0 ? "-" : "") + "\(whole)"
        }
        let g = gcd(num, den)
        num /= g
        den /= g
        if whole == 0 {
            return (negative ? "-" : "") + "\(num)/\(den)"
        }
        return (negative ? "-" : "") + "\(whole) \(num)/\(den)"
    }

    /// Inches with the inch mark: 2 9/32"
    static func inches(_ inches: Double, denominator: Int) -> String {
        fraction(inches, denominator: denominator) + "\""
    }

    /// Signed difference between the rounded fraction and the true value, in inches.
    static func roundingError(_ inches: Double, denominator: Int) -> Double {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return 0 }
        let rounded = (inches * Double(denominator)).rounded() / Double(denominator)
        return rounded - inches
    }

    /// "a hair over" / "a hair under" style note for a rounded value, or nil if exact.
    static func roundingNote(_ inches: Double, denominator: Int) -> String? {
        let err = roundingError(inches, denominator: denominator)
        if abs(err) < 0.0005 { return nil }
        let thou = String(format: "%.3f", abs(err))
        return err > 0 ? "rounded up \(thou)\"" : "rounded down \(thou)\""
    }

    /// 5' 2 1/4"
    static func feetInches(_ inches: Double, denominator: Int) -> String {
        guard inches.isFinite, abs(inches) * Double(denominator) < 1e15 else { return decimal(inches, places: 3) + "\"" }
        let negative = inches < 0
        let units = Int((abs(inches) * Double(denominator)).rounded())
        let perFoot = 12 * denominator
        let feet = units / perFoot
        let remUnits = units % perFoot
        let rem = Double(remUnits) / Double(denominator)
        let sign = negative ? "-" : ""
        if feet == 0 { return sign + fraction(rem, denominator: denominator) + "\"" }
        return sign + "\(feet)' " + fraction(rem, denominator: denominator) + "\""
    }

    static func decimal(_ x: Double, places: Int = 3) -> String {
        String(format: "%.\(places)f", x)
    }

    static func degrees(_ x: Double) -> String {
        String(format: "%.1f°", x)
    }

    static func money(_ x: Double) -> String {
        String(format: "$%.2f", x)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
