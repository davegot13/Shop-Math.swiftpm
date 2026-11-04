import SwiftUI

struct AnglesView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case frame = "Flat frame"
        case box = "Box"
        case sloped = "Sloped box"
        var id: String { rawValue }
    }

    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage("angles_kind") private var kindRaw = Kind.frame.rawValue
    @AppStorage("angles_sides") private var sides = 4
    @AppStorage("angles_tilt") private var tiltText = "15"
    @AppStorage(LengthField.anglesAcross.key) private var acrossText = ""
    @AppStorage(LengthField.anglesStock.key) private var stockText = ""
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    private var kind: Kind { Kind(rawValue: kindRaw) ?? .frame }

    private var settings: SawSettings? {
        switch kind {
        case .frame: return Angles.flatFrame(sides: sides)
        case .box: return Angles.straightBox(sides: sides)
        case .sloped:
            guard let t = number(tiltText) else { return nil }
            return Angles.compound(sides: sides, tiltFromVertical: t)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Project", selection: $kindRaw) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(kindHelp)
                }

                Section {
                    Stepper("Sides: \(sides)", value: $sides, in: 3...24)
                    if kind == .sloped {
                        NumberField(label: "Side tilt", text: $tiltText, suffix: "°",
                                    caption: "From vertical. 0° is straight sides.")
                    }
                }

                if let s = settings {
                    Section {
                        BigResult(title: "Miter", value: Format.degrees(s.miter))
                        BigResult(title: "Bevel", value: Format.degrees(s.bevel))
                        ResultRow(label: "Angle between sides", value: Format.degrees(180 - 360 / Double(sides)))
                        if kind == .sloped, let t = number(tiltText), t > 0 {
                            Callout(kind: .info, text: "Rip the top and bottom edges of each side at a \(Format.degrees(t)) bevel so the box sits flat and the rim is level.")
                        }
                        if kind == .box {
                            Callout(kind: .info, text: "Cut with the board flat on the saw and the blade tilted. For narrow stock you can stand it on edge against the fence and use a \(Format.degrees(180 / Double(sides))) miter instead.")
                        }
                    } header: {
                        Text("Saw settings")
                    } footer: {
                        Text("Board flat on the saw table. Miter is the table angle from the 0° detent, bevel is the blade tilt from vertical. Cut a test pair before committing good stock; small errors multiply by \(sides * 2) cuts.")
                    }
                } else {
                    Section {
                        Callout(kind: .warning, text: "Tilt must be between 0° and 90°.")
                    }
                }

                if kind != .sloped {
                    sizeSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Angles")
            .settingsButton()
        }
    }

    private var kindHelp: String {
        switch kind {
        case .frame: return "Picture frames, mirrors, and polygon trays lying flat."
        case .box: return "Boxes with straight sides and mitered corners."
        case .sloped: return "Planters, hoppers, and trays with sides leaning out."
        }
    }

    @ViewBuilder private var sizeSection: some View {
        Section {
            MeasureField(label: "Outside, flat to flat", text: $acrossText)
            MeasureField(label: kind == .frame ? "Frame stock width" : "Side thickness", text: $stockText)
            if let d = unit.inches(acrossText), d > 0 {
                let outside = Angles.edgeLength(acrossFlats: d, sides: sides)
                ResultRow(label: "Outside edge (long point)", value: unit.length(outside, precision: precision))
                if let w = unit.inches(stockText), w > 0, d - 2 * w > 0 {
                    let inside = Angles.edgeLength(acrossFlats: d - 2 * w, sides: sides)
                    ResultRow(label: "Inside edge (short point)", value: unit.length(inside, precision: precision))
                }
            }
        } header: {
            Text("Piece length")
        } footer: {
            Text("Cut every piece to the same long point length. Measured flat to flat across the outside, not corner to corner.")
        }
    }
}
