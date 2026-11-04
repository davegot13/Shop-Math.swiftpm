import SwiftUI

@MainActor
final class LumberStore: ObservableObject {
    private static let key = "lumber.items"

    @Published var items: [LumberItem] = [] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([LumberItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

struct BoardFeetView: View {
    @EnvironmentObject private var store: LumberStore
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial
    @AppStorage(LengthField.bfThickness.key) private var thicknessText = LengthField.bfThickness.imperialDefault
    @AppStorage(LengthField.bfWidth.key) private var widthText = LengthField.bfWidth.imperialDefault
    @AppStorage(LengthField.bfLength.key) private var lengthText = LengthField.bfLength.imperialDefault
    @AppStorage("bf_quantity") private var quantity = 1
    @AppStorage("bf_price") private var priceText = "0"
    @AppStorage("bf_waste") private var wasteText = "20"
    @State private var name = ""
    @State private var confirmClear = false

    private struct Dims {
        let t: Double
        let w: Double
        let l: Double
    }

    private var dims: Dims? {
        guard let t = unit.inches(thicknessText), t > 0,
              let w = unit.inches(widthText), w > 0,
              let l = unit.inches(lengthText), l > 0 else { return nil }
        return Dims(t: t, w: w, l: l)
    }

    private var price: Double { max(0, number(priceText) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MeasureField(label: "Thickness", text: $thicknessText)
                    MeasureField(label: "Width", text: $widthText)
                    MeasureField(label: "Length", text: $lengthText,
                                 caption: unit == .imperial ? "Inches, or feet like 8'" : "mm, or meters like 2.4 m")
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                    NumberField(label: "Price per board foot", text: $priceText, prefix: "$")
                } header: {
                    Text(unit == .imperial ? "Board, actual size in inches" : "Board, actual size in mm")
                }

                if let d = dims {
                    let bf = BoardFeet.of(thickness: d.t, width: d.w, length: d.l, quantity: quantity)
                    Section {
                        BigResult(title: "Board feet",
                                  value: Format.decimal(bf, places: 2),
                                  detail: resultDetail(bf))
                        if price > 0 {
                            ResultRow(label: "Cost", value: Format.money(bf * price))
                        }
                        TextField("Name (optional), e.g. Maple", text: $name)
                        Button {
                            store.items.append(LumberItem(
                                name: name.trimmingCharacters(in: .whitespaces),
                                thickness: d.t, width: d.w, length: d.l,
                                quantity: quantity, pricePerBoardFoot: price))
                            name = ""
                        } label: {
                            Label("Add to lumber list", systemImage: "plus.circle.fill")
                        }
                    } footer: {
                        Text(unit == .imperial
                             ? "Thickness × width × length in inches ÷ 144."
                             : "Sizes convert to inches, then thickness × width × length ÷ 144. One board foot is 0.00236 m³.")
                    }
                }

                listSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Board Feet")
            .settingsButton()
            .confirmationDialog("Clear the lumber list?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear list", role: .destructive) { store.items.removeAll() }
            }
        }
    }

    @ViewBuilder private var listSection: some View {
        if !store.items.isEmpty {
            Section {
                ForEach(store.items) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.name.isEmpty ? "Board" : item.name).font(.headline)
                            Spacer()
                            Text("\(Format.decimal(item.boardFeet, places: 2)) bf")
                                .font(.body.monospacedDigit())
                        }
                        HStack {
                            Text(describe(item))
                            Spacer()
                            if item.pricePerBoardFoot > 0 {
                                Text(Format.money(item.cost))
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete { store.items.remove(atOffsets: $0) }

                NumberField(label: "Waste allowance", text: $wasteText, suffix: "%")
                let totals = LumberTotals.of(store.items, wastePercent: number(wasteText) ?? 0)
                ResultRow(label: "Total", value: "\(Format.decimal(totals.boardFeet, places: 2)) bf")
                ResultRow(label: "With waste", value: "\(Format.decimal(totals.boardFeetWithWaste, places: 2)) bf")
                if unit == .metric {
                    ResultRow(label: "Volume with waste", value: Format.cubicMeters(boardFeet: totals.boardFeetWithWaste))
                }
                if totals.cost > 0 {
                    ResultRow(label: "Cost", value: Format.money(totals.cost))
                    ResultRow(label: "Cost with waste", value: Format.money(totals.costWithWaste))
                }
                Button("Clear list", role: .destructive) { confirmClear = true }
            } header: {
                Text("Lumber list")
            } footer: {
                Text("Swipe left on a board to remove it.")
            }
        }
    }

    /// Per-piece board feet when buying more than one, and cubic meters in metric.
    private func resultDetail(_ bf: Double) -> String? {
        var parts: [String] = []
        if quantity > 1 { parts.append("\(Format.decimal(bf / Double(quantity), places: 2)) each") }
        if unit == .metric { parts.append(Format.cubicMeters(boardFeet: bf)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func describe(_ item: LumberItem) -> String {
        var s = unit.dimensions([item.thickness, item.width, item.length], precision: 16)
        if item.quantity > 1 { s += "  ×\(item.quantity)" }
        if item.pricePerBoardFoot > 0 { s += "  @ \(Format.money(item.pricePerBoardFoot))" }
        return s
    }
}
