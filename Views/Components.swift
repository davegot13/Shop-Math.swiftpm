import SwiftUI
import UIKit

// MARK: - Shared settings

enum Keys {
    static let kerf = LengthField.kerf.key
    static let precision = "settings_precision"
    static let tilt = "settings_tilt"
    static let units = UnitSwitcher.unitKey
}

/// Parses a stored kerf entry to inches, falling back to 1/8" if it can't be used.
func kerfValue(_ text: String, unit: UnitSystem) -> Double {
    if let v = unit.inches(text), v >= 0, v < 1 { return v }
    return 0.125
}

/// Shown under a kerf field when the entry can't be used.
struct KerfWarning: View {
    let text: String
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    var body: some View {
        if let v = unit.inches(text), v >= 0, v < 1 {
            EmptyView()
        } else {
            Callout(kind: .warning, text: unit == .imperial
                    ? "Kerf must be under 1\". Using 1/8\" until it's fixed."
                    : "Kerf must be under 25.4 mm. Using 3.2 mm until it's fixed.")
        }
    }
}

// MARK: - Input

/// A length field that accepts fractions, feet and inches, metric units, and simple math.
struct MeasureField: View {
    let label: String
    @Binding var text: String
    var caption: String? = nil
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    /// A read-back of the entry in both units, a gray prompt when empty, or a red error.
    private var status: (String, Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return ("Enter a value", false) }
        guard let v = unit.inches(trimmed) else { return ("Can't read that", true) }
        switch unit {
        case .imperial:
            return (Format.decimal(v, places: 4) + "\" · " + Format.mm(v), false)
        case .metric:
            return (Format.mmNumber(v, places: 2) + " mm · " + Format.inches(v, denominator: 32), false)
        }
    }

    var body: some View {
        FieldRow(label: label, caption: caption, status: status.0, statusIsError: status.1,
                 suffix: unit == .metric ? "mm" : "") {
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.body.monospacedDigit())
        }
    }
}

/// A plain number field (degrees, percent, dollars).
struct NumberField: View {
    let label: String
    @Binding var text: String
    var prefix: String = ""
    var suffix: String = ""
    var caption: String? = nil

    private var status: (String, Bool)? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return ("Enter a number", false) }
        return number(text) == nil ? ("Enter a number", true) : nil
    }

    var body: some View {
        FieldRow(label: label, caption: caption, status: status?.0, statusIsError: status?.1 ?? false,
                 prefix: prefix, suffix: suffix) {
            TextField("0", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
        }
    }
}

/// Shared layout for entry rows. The label and a filled entry box share the top line; the
/// caption sits below at full width and wraps, with the read-back under the entry on the right.
/// Tapping the label, the gap, or the caption starts editing; the entry box keeps its own
/// text gestures (caret placement, double-tap selection, the loupe) untouched. At accessibility text sizes the entry box drops
/// below its label so long values never clip.
struct FieldRow<Field: View>: View {
    let label: String
    let caption: String?
    let status: String?
    let statusIsError: Bool
    var prefix: String = ""
    let suffix: String
    @ViewBuilder let field: () -> Field

    @FocusState private var focused: Bool
    @ScaledMetric(relativeTo: .body) private var minFieldWidth: CGFloat = 90
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let top = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))

        VStack(alignment: .leading, spacing: 4) {
            top {
                Text(label)
                    .layoutPriority(1)
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                if !stacked {
                    Spacer(minLength: 8)
                        .contentShape(Rectangle())
                        .onTapGesture { focused = true }
                }
                entry
            }
            notes
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
        }
        .padding(.vertical, 2)
    }

    private var entry: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !prefix.isEmpty {
                Text(prefix).foregroundStyle(.secondary)
            }
            field()
                .focused($focused)
                .accessibilityLabel(label)
                .accessibilityHint(caption ?? "")
                .frame(minWidth: minFieldWidth, maxWidth: 180)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
            if !suffix.isEmpty {
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }

    /// Caption and read-back on one line when they fit, otherwise caption first (wrapping)
    /// and the read-back on its own line at the right.
    @ViewBuilder private var notes: some View {
        if caption != nil || status != nil {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    captionText(wrapping: false)
                    Spacer(minLength: 12)
                    statusText
                }
                VStack(alignment: .leading, spacing: 3) {
                    captionText(wrapping: true)
                    statusText
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder private func captionText(wrapping: Bool) -> some View {
        if let caption {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(wrapping ? nil : 1)
                .fixedSize(horizontal: false, vertical: wrapping)
        }
    }

    @ViewBuilder private var statusText: some View {
        if let status {
            Text(status)
                .font(.caption.monospacedDigit())
                .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

func number(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

// MARK: - Output

/// The headline number on each screen, sized to read from across the bench.
struct BigResult: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(.body.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

struct Callout: View {
    enum Kind { case info, warning }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text).font(.footnote)
        } icon: {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(kind == .warning ? Color.orange : Color.accentColor)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.kerf) private var kerf = LengthField.kerf.imperialDefault
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.tilt) private var tilt: BladeTilt = .awayFromFence
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    private var unitBinding: Binding<UnitSystem> {
        Binding(get: { unit }, set: { UnitSwitcher.switchTo($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: unitBinding) {
                        ForEach(UnitSystem.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if unit == .imperial {
                        PrecisionPicker(precision: $precision)
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text(unit == .imperial
                         ? "Fractions round to the size above. Switching units converts everything you've entered."
                         : "Results show to 0.1 mm. Switching units converts everything you've entered.")
                }

                Section {
                    MeasureField(label: "Blade kerf", text: $kerf,
                                 caption: unit == .imperial
                                    ? "Full kerf is about 1/8, thin kerf about 3/32. Use your blade's spec."
                                    : "Full kerf is about 3.2, thin kerf about 2.4. Use your blade's spec.")
                    KerfWarning(text: kerf)
                    Picker("Blade tilts", selection: $tilt) {
                        ForEach(BladeTilt.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Table saw")
                } footer: {
                    Text("Most jobsite saws, Skil included, tilt left. With the fence right of the blade that is away from the fence.")
                }

                Section {
                    Text(unit == .imperial
                         ? "Length fields take 1.75, 1 3/4, 1-3/4, 7' 4 1/2\", 7'-4\", 19 mm, and math like (3 + 1/2) × 2. Put spaces around a minus to subtract."
                         : "Length fields are in mm and take 139.7, 14 cm, 2.4 m, 5 1/2\", 8', and math like (450 + 18) × 2. Put spaces around a minus to subtract.")
                        .font(.footnote)
                } header: {
                    Text("Entering measurements")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct PrecisionPicker: View {
    @Binding var precision: Int

    var body: some View {
        Picker("Precision", selection: $precision) {
            Text("1/8").tag(8)
            Text("1/16").tag(16)
            Text("1/32").tag(32)
            Text("1/64").tag(64)
        }
        .pickerStyle(.segmented)
    }
}

/// Adds the in/mm toggle and the settings gear to a screen's toolbar.
struct SettingsButton: ViewModifier {
    var showsUnits = true
    @State private var showing = false
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsUnits {
                        unitButton
                    }

                    Button {
                        showing = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showing) {
                SettingsView()
            }
    }

    private var unitButton: some View {
        Button {
            UnitSwitcher.switchTo(UnitSwitcher.current().other)
        } label: {
            Text(unit.symbol)
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
        }
        .accessibilityLabel("Units: \(unit.name). Switch to \(unit.other.name).")
    }
}

extension View {
    func settingsButton(showsUnits: Bool = true) -> some View {
        modifier(SettingsButton(showsUnits: showsUnits))
    }
}
