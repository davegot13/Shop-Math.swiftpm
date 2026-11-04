import SwiftUI

struct EndGrainView: View {
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.kerf) private var kerfText = LengthField.kerf.imperialDefault
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    @AppStorage(LengthField.egLength.key) private var lengthText = LengthField.egLength.imperialDefault
    @AppStorage(LengthField.egWidth.key) private var widthText = LengthField.egWidth.imperialDefault
    @AppStorage(LengthField.egThickness.key) private var thicknessText = LengthField.egThickness.imperialDefault
    @AppStorage(LengthField.egStripWidth.key) private var stripWidthText = LengthField.egStripWidth.imperialDefault
    @AppStorage(LengthField.egPanel.key) private var panelText = LengthField.egPanel.imperialDefault
    @AppStorage(LengthField.egFlatten1.key) private var flatten1Text = LengthField.egFlatten1.imperialDefault
    @AppStorage(LengthField.egFlatten2.key) private var flatten2Text = LengthField.egFlatten2.imperialDefault
    @AppStorage(LengthField.egEdgeTrim.key) private var edgeTrimText = LengthField.egEdgeTrim.imperialDefault
    @AppStorage(LengthField.egEndTrim.key) private var endTrimText = LengthField.egEndTrim.imperialDefault
    @AppStorage("eg_yield") private var yieldText = "55"

    private var plan: EndGrainPlan? {
        guard let l = unit.inches(lengthText),
              let w = unit.inches(widthText),
              let t = unit.inches(thicknessText),
              let sw = unit.inches(stripWidthText),
              let p = unit.inches(panelText),
              let f1 = unit.inches(flatten1Text),
              let f2 = unit.inches(flatten2Text),
              let et = unit.inches(edgeTrimText),
              let nt = unit.inches(endTrimText),
              let y = number(yieldText) else { return nil }
        return EndGrainPlan.make(EndGrainInput(
            boardLength: l, boardWidth: w, boardThickness: t,
            stripWidth: sw, panelThickness: p,
            firstFlatten: f1, finalFlatten: f2,
            edgeTrim: et, endTrim: nt,
            kerf: kerfValue(kerfText, unit: unit), yieldPercent: y))
    }

    private func inch(_ v: Double) -> String { unit.length(v, precision: precision) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MeasureField(label: "Length", text: $lengthText, caption: "Along each slice")
                    MeasureField(label: "Width", text: $widthText, caption: "Across the slices")
                    MeasureField(label: "Thickness", text: $thicknessText)
                } header: {
                    Text("Finished board")
                }

                Section {
                    MeasureField(label: "Strip width", text: $stripWidthText,
                                 caption: "Each strip's share of the first panel's width")
                    MeasureField(label: "Panel thickness", text: $panelText,
                                 caption: "First glue-up as glued, before flattening")
                } header: {
                    Text("First glue-up")
                }

                Section {
                    MeasureField(label: "Flatten first panel", text: $flatten1Text, caption: "Total removed")
                    MeasureField(label: "Flatten final board", text: $flatten2Text, caption: "Total removed on the drum sander")
                    MeasureField(label: "Edge trim", text: $edgeTrimText, caption: "Off each glue-up's edges, total")
                    MeasureField(label: "End squaring cut", text: $endTrimText)
                    MeasureField(label: "Blade kerf", text: $kerfText)
                    KerfWarning(text: kerfText)
                    NumberField(label: "Lumber yield", text: $yieldText, suffix: "%",
                                caption: "Usable share of rough stock after milling and defects")
                } header: {
                    Text("Allowances")
                }

                if let p = plan {
                    resultSections(p)
                } else {
                    Section {
                        Callout(kind: .warning, text: "Check the inputs. Panel thickness has to be more than the flattening allowance, and yield between 1 and 100.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("End Grain Board")
            .settingsButton()
        }
    }

    @ViewBuilder private func resultSections(_ p: EndGrainPlan) -> some View {
        Section {
            BigResult(title: "Strips",
                      value: "\(p.strips) × \(inch(p.stripLength))",
                      detail: "\(inch(p.stripWidth)) wide by \(inch(p.stripHeight)) tall")
            ResultRow(label: "Net strip stock", value: "\(Format.decimal(p.netBoardFeet, places: 2)) bf")
            ResultRow(label: "Rough lumber to buy", value: "\(Format.decimal(p.roughBoardFeet, places: 2)) bf")
            if unit == .metric {
                ResultRow(label: "Rough lumber volume", value: Format.cubicMeters(boardFeet: p.roughBoardFeet))
            }
        } header: {
            Text("Cut list")
        }

        Section {
            step(1, "Rip \(p.strips) strips, each \(inch(p.stripLength)) long.")
            step(2, "Glue the first panel: \(inch(p.panelWidth)) wide × \(inch(p.panelLength)) long. Flatten to \(inch(p.sliceFace)).")
            step(3, "Square one end, then crosscut \(p.slices) slices at \(inch(p.sliceWidth)).")
            step(4, "Turn the slices end grain up and glue. As glued: \(inch(p.asGluedLength)) × \(inch(p.asGluedWidth)).")
            step(5, "Flatten and trim to \(inch(p.finishedLength)) × \(inch(p.finishedWidth)) × \(inch(p.finishedThickness)).")
        } header: {
            Text("Steps")
        } footer: {
            Text("Strip counts round up, so the finished size can come out a little larger than the target. Trim to size or drop a strip.")
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text).font(.callout.monospacedDigit())
        }
    }
}
