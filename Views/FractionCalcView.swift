import SwiftUI

/// A plain fraction calculator. It has no units: you know what you're measuring in, and the
/// in/mm setting on the other tabs never changes it. ' still multiplies by 12 so tape readings
/// like 7' 4 1/2 add up.
struct FractionCalcView: View {
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage("calc_expression") private var expression = ""
    @State private var justEvaluated = false

    private var result: Double? { MeasureParser.value(expression) }

    private let rows: [[String]] = [
        ["C", "(", ")", "⌫"],
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        ["0", ".", "/", "+"],
        ["'", "\"", "space", "="]
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    display
                    PrecisionPicker(precision: $precision)
                    keypad
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Fractions")
            .navigationBarTitleDisplayMode(.inline)
            .settingsButton(showsUnits: false)
        }
    }

    // MARK: Display

    private var display: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(expression.isEmpty ? "1 3/4 + 5/8" : expression)
                .font(.title3.monospacedDigit())
                .foregroundStyle(expression.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if let v = result {
                Text(Format.fraction(v, denominator: precision))
                    .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(Format.trimmed(v, places: 4))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let note = roundingNote(v) {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            } else if !expression.isEmpty {
                Text("…").font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomTrailing)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// How far the fraction shown is from the exact result, when it isn't exact.
    private func roundingNote(_ v: Double) -> String? {
        let err = Format.roundingError(v, denominator: precision)
        if abs(err) < 0.0005 { return nil }
        return (err > 0 ? "rounded up " : "rounded down ") + Format.decimal(abs(err), places: 3)
    }

    // MARK: Keypad

    private var keypad: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            tap(key)
                        } label: {
                            Text(key == "space" ? "␣" : key)
                                .font(.title2.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.bordered)
                        .tint(tint(for: key))
                        .accessibilityLabel(spoken(key))
                    }
                }
            }
        }
    }

    private func tint(for key: String) -> Color {
        switch key {
        case "=": return .accentColor
        case "÷", "×", "−", "+": return .orange
        case "C", "⌫": return .red
        default: return .gray
        }
    }

    private func spoken(_ key: String) -> String {
        switch key {
        case "'": return "feet"
        case "\"": return "inches"
        case "/": return "fraction bar"
        case "space": return "space"
        case "⌫": return "delete"
        case "C": return "clear"
        default: return key
        }
    }

    private func tap(_ key: String) {
        switch key {
        case "C":
            expression = ""
        case "⌫":
            while expression.hasSuffix(" ") { expression.removeLast() }
            expression = String(expression.dropLast())
            while expression.hasSuffix(" ") { expression.removeLast() }
        case "=":
            if let v = result {
                expression = Format.inchEntry(v)
                justEvaluated = true
            }
            return
        case "÷", "×", "−", "+":
            while expression.hasSuffix(" ") { expression.removeLast() }
            if expression.isEmpty && key != "−" { break }
            expression += expression.isEmpty ? "-" : " \(key) "
        case "space":
            if !expression.isEmpty && !expression.hasSuffix(" ") { expression += " " }
        default:
            // A digit right after = starts a new calculation.
            if justEvaluated, key.first?.isNumber == true || key == "." || key == "(" {
                expression = ""
            }
            expression += key
        }
        justEvaluated = false
    }
}
