import Foundation

// MARK: - Unit system
//
// All math runs in inches. The unit system only decides how entries are read and how results
// are shown. Metric entries are millimeters; results show to 0.1 mm.

enum UnitSystem: String, CaseIterable, Identifiable, Codable {
    case imperial
    case metric

    var id: String { rawValue }

    /// Short label for the toolbar button.
    var symbol: String { self == .imperial ? "in" : "mm" }

    var name: String { self == .imperial ? "Inches" : "Millimeters" }

    var other: UnitSystem { self == .imperial ? .metric : .imperial }

    private var parseUnit: MeasureParser.Unit { self == .imperial ? .inch : .millimeter }

    /// Reads a length entry typed in this unit system and returns inches.
    func inches(_ text: String) -> Double? {
        guard let v = MeasureParser.value(text, unit: parseUnit) else { return nil }
        return self == .imperial ? v : v / 25.4
    }

    /// A result for display: 2 9/32" or 57.9 mm.
    func length(_ inches: Double, precision: Int) -> String {
        switch self {
        case .imperial: return Format.inches(inches, denominator: precision)
        case .metric: return Format.mm(inches)
        }
    }

    /// A length list like 3/4 × 5 1/2 × 96" or 19.1 × 139.7 × 2438.4 mm.
    func dimensions(_ values: [Double], precision: Int) -> String {
        switch self {
        case .imperial:
            return values.map { Format.fraction($0, denominator: precision) }.joined(separator: " × ") + "\""
        case .metric:
            return values.map { Format.mmNumber($0) }.joined(separator: " × ") + " mm"
        }
    }

    /// Second line under a headline result: the decimal and rounding in imperial, the inch
    /// equivalent in metric.
    func detail(_ inches: Double, precision: Int) -> String {
        switch self {
        case .imperial:
            var s = Format.decimal(inches, places: 3) + "\" · " + Format.mm(inches)
            if let note = Format.roundingNote(inches, denominator: precision) { s += " · " + note }
            return s
        case .metric:
            return Format.mmNumber(inches, places: 2) + " mm · " + Format.inches(inches, denominator: 32)
        }
    }

    /// Text for an input field that reads back as the same length in this unit system.
    func entryText(_ inches: Double) -> String {
        switch self {
        case .imperial: return Format.inchEntry(inches)
        case .metric: return Format.mmEntry(inches)
        }
    }

    /// Rewrites an entry typed in this unit system as the same length in `target`.
    /// Text that is empty or can't be read is left as it is.
    func convert(_ text: String, to target: UnitSystem) -> String {
        if target == self { return text }
        guard let v = inches(text) else { return text }
        return target.entryText(v)
    }
}

// MARK: - Metric formatting

extension Format {
    static let mmPerInch = 25.4
    static let cubicMetersPerBoardFoot: Double = 144 * 0.0254 * 0.0254 * 0.0254

    /// Millimeters as a bare number, trailing zeros trimmed: 139.7, 140, 3.18.
    static func mmNumber(_ inches: Double, places: Int = 1) -> String {
        trimmed(inches * mmPerInch, places: places)
    }

    /// 57.9 mm
    static func mm(_ inches: Double) -> String {
        mmNumber(inches) + " mm"
    }

    /// 0.0094 m³
    static func cubicMeters(boardFeet: Double) -> String {
        String(format: "%.4f m³", boardFeet * cubicMetersPerBoardFoot)
    }

    /// Entry text in mm, kept to 0.001 mm so a converted fraction converts back exactly.
    static func mmEntry(_ inches: Double) -> String {
        trimmed(inches * mmPerInch, places: 3)
    }

    /// Entry text in inches: a 1/64 fraction when the value is within 0.00003" of one (close
    /// enough to absorb a trip through mm), otherwise a decimal precise enough to convert back.
    static func inchEntry(_ inches: Double) -> String {
        guard inches.isFinite else { return "0" }
        let sixtyFourths = inches * 64
        if abs(inches) < 1e9, abs(sixtyFourths - sixtyFourths.rounded()) < 0.002 {
            return fraction(inches, denominator: 64)
        }
        return trimmed(inches, places: 6)
    }

    /// Rounds half away from zero (19.05 → 19.1) and trims trailing zeros. The small nudge keeps
    /// values like 19.05, stored in binary as 19.04999…, from rounding down.
    static func trimmed(_ x: Double, places: Int) -> String {
        guard x.isFinite, abs(x) < 1e12 else { return x.isFinite ? String(format: "%.0f", x) : "0" }
        var scale = 1.0
        for _ in 0..<max(0, places) { scale *= 10 }
        let magnitude = (abs(x) * scale + 0.5 + 1e-7).rounded(.down) / scale
        var s = String(format: "%.\(places)f", x < 0 ? -magnitude : magnitude)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" { s = "0" }
        return s
    }
}

// MARK: - Stored entries

/// Every length entry the app remembers, with its default in inches.
enum LengthField: String, CaseIterable {
    case kerf = "settings_kerf"
    case cleatBoard = "cleat_board"
    case cleatTarget = "cleat_target"
    case cleatStrip = "cleat_strip"
    case cleatThickness = "cleat_thickness"
    case cleatTestFence = "cleat_testFence"
    case cleatTestOffcut = "cleat_testOffcut"
    case bfThickness = "bf_thickness"
    case bfWidth = "bf_width"
    case bfLength = "bf_length"
    case anglesAcross = "angles_across"
    case anglesStock = "angles_stock"
    case egLength = "eg_length"
    case egWidth = "eg_width"
    case egThickness = "eg_thickness"
    case egStripWidth = "eg_stripWidth"
    case egPanel = "eg_panel"
    case egFlatten1 = "eg_flatten1"
    case egFlatten2 = "eg_flatten2"
    case egEdgeTrim = "eg_edgeTrim"
    case egEndTrim = "eg_endTrim"

    var key: String { rawValue }

    var imperialDefault: String {
        switch self {
        case .kerf: return "1/8"
        case .cleatBoard: return "5 1/2"
        case .cleatTarget: return "3"
        case .cleatStrip: return "3"
        case .cleatThickness: return "3/4"
        case .cleatTestFence, .cleatTestOffcut, .anglesAcross, .anglesStock: return ""
        case .bfThickness: return "1"
        case .bfWidth: return "6"
        case .bfLength: return "96"
        case .egLength: return "16"
        case .egWidth: return "12"
        case .egThickness: return "1 1/2"
        case .egStripWidth: return "1 1/2"
        case .egPanel: return "1 3/4"
        case .egFlatten1, .egFlatten2: return "1/8"
        case .egEdgeTrim, .egEndTrim: return "1/2"
        }
    }
}

enum UnitSwitcher {
    static let unitKey = "settings_units"

    /// Keys from version 1.0, which used dots. iOS doesn't reliably report changes to keys
    /// with dots, so they were renamed with underscores; this carries saved values across.
    static let legacyKeys = [
        "angles.across", "angles.kind", "angles.sides", "angles.stock", "angles.tilt", "app.tab",
        "bf.length", "bf.price", "bf.quantity", "bf.thickness", "bf.waste", "bf.width",
        "calc.expression", "cleat.board", "cleat.method", "cleat.solveFrom", "cleat.strip",
        "cleat.target", "cleat.thickness", "eg.edgeTrim", "eg.endTrim", "eg.flatten1",
        "eg.flatten2", "eg.length", "eg.panel", "eg.stripWidth", "eg.thickness", "eg.width",
        "eg.yield", "settings.kerf", "settings.precision", "settings.tilt"
    ]

    /// Copies each 1.0 value to its new key (unless the new key already has one) and removes the old key.
    static func migrateLegacyKeys(_ d: UserDefaults = .standard) {
        for old in legacyKeys {
            guard let value = d.object(forKey: old) else { continue }
            let new = old.replacingOccurrences(of: ".", with: "_")
            if d.object(forKey: new) == nil { d.set(value, forKey: new) }
            d.removeObject(forKey: old)
        }
    }

    /// Run once at launch, before any screen reads its entries.
    static func prepare(_ d: UserDefaults = .standard) {
        migrateLegacyKeys(d)
        ensureStored(d)
    }

    static func current(_ d: UserDefaults = .standard) -> UnitSystem {
        UnitSystem(rawValue: d.string(forKey: unitKey) ?? "") ?? .imperial
    }

    /// Writes any entry that has never been saved, in the current unit system, so a default
    /// like "5 1/2" is never read as millimeters.
    static func ensureStored(_ d: UserDefaults = .standard) {
        let unit = current(d)
        for field in LengthField.allCases where d.string(forKey: field.key) == nil {
            d.set(UnitSystem.imperial.convert(field.imperialDefault, to: unit), forKey: field.key)
        }
    }

    /// Converts every stored entry to `target` and makes it the current unit system.
    static func switchTo(_ target: UnitSystem, _ d: UserDefaults = .standard) {
        let from = current(d)
        guard from != target else { return }
        ensureStored(d)
        for field in LengthField.allCases {
            if let text = d.string(forKey: field.key) {
                d.set(from.convert(text, to: target), forKey: field.key)
            }
        }
        d.set(target.rawValue, forKey: unitKey)
    }
}
