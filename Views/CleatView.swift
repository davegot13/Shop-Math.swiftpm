import SwiftUI

struct CleatView: View {
    enum Method: String, CaseIterable, Identifiable {
        case split = "Rip board in half"
        case edge = "Bevel one edge"
        var id: String { rawValue }
    }

    enum SolveFrom: String, CaseIterable, Identifiable {
        case board = "Board width"
        case cleat = "Cleat width"
        var id: String { rawValue }
    }

    @AppStorage(Keys.kerf) private var kerfText = LengthField.kerf.imperialDefault
    @AppStorage(Keys.precision) private var precision = 32
    @AppStorage(Keys.tilt) private var tilt: BladeTilt = .awayFromFence
    @AppStorage(Keys.units) private var unit: UnitSystem = .imperial

    @AppStorage("cleat_method") private var methodRaw = Method.split.rawValue
    @AppStorage("cleat_solveFrom") private var solveRaw = SolveFrom.board.rawValue
    @AppStorage(LengthField.cleatBoard.key) private var boardText = LengthField.cleatBoard.imperialDefault
    @AppStorage(LengthField.cleatTarget.key) private var targetText = LengthField.cleatTarget.imperialDefault
    @AppStorage(LengthField.cleatStrip.key) private var stripText = LengthField.cleatStrip.imperialDefault
    @AppStorage(LengthField.cleatThickness.key) private var thicknessText = LengthField.cleatThickness.imperialDefault
    @AppStorage(LengthField.cleatTestFence.key) private var testFenceText = ""
    @AppStorage(LengthField.cleatTestOffcut.key) private var testOffcutText = ""

    private var method: Method { Method(rawValue: methodRaw) ?? .split }
    private var solveFrom: SolveFrom { SolveFrom(rawValue: solveRaw) ?? .board }
    private var kerf: Double { kerfValue(kerfText, unit: unit) }
    private var thickness: Double? { unit.inches(thicknessText) }

    private var split: CleatSplit? {
        guard let t = thickness else { return nil }
        switch solveFrom {
        case .board:
            guard let w = unit.inches(boardText) else { return nil }
            return CleatSplit.fromBoard(width: w, thickness: t, kerf: kerf, tilt: tilt)
        case .cleat:
            guard let c = unit.inches(targetText) else { return nil }
            return CleatSplit.fromCleat(longFace: c, thickness: t, kerf: kerf, tilt: tilt)
        }
    }

    private var edge: CleatEdgeBevel? {
        guard let t = thickness, let s = unit.inches(stripText) else { return nil }
        return CleatEdgeBevel.make(stripWidth: s, thickness: t, tilt: tilt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Method", selection: $methodRaw) {
                        ForEach(Method.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                inputSection
                resultSection

                if method == .split {
                    testCutSection
                }

                Section("How to set the fence") {
                    Text("Tilt the blade to 45°. Hook a rule on the fence and measure to the fence side of a tooth right where it comes out of the throat plate, at table level. The fence scale is not reliable once the blade is tilted.")
                        .font(.footnote)
                    if let t = thickness {
                        Text("Raise the blade until the teeth clear the top of the board. The cut runs \(len(t * 2.0.squareRoot())) along the slope.")
                            .font(.footnote)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("French Cleats")
            .settingsButton()
        }
    }

    private func len(_ inches: Double) -> String { unit.length(inches, precision: precision) }

    private var minPiece: String { unit == .imperial ? "1\"" : "25.4 mm" }

    private func correction(_ inches: Double) -> String {
        switch unit {
        case .imperial: return "\(Format.inches(inches, denominator: 64)) (\(Format.decimal(inches, places: 3))\")"
        case .metric: return Format.mm(inches)
        }
    }

    // MARK: Sections

    @ViewBuilder private var inputSection: some View {
        Section {
            switch method {
            case .split:
                Picker("Start from", selection: $solveRaw) {
                    ForEach(SolveFrom.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                if solveFrom == .board {
                    MeasureField(label: "Board width", text: $boardText)
                } else {
                    MeasureField(label: "Cleat width", text: $targetText, caption: "Wide face of each cleat")
                }
            case .edge:
                MeasureField(label: "Strip width", text: $stripText, caption: "Already ripped to width")
            }
            MeasureField(label: "Thickness", text: $thicknessText,
                         caption: unit == .imperial
                            ? "Measure it. 3/4 plywood is often 23/32."
                            : "Measure it. Sheet goods often run under their nominal size.")
            MeasureField(label: "Blade kerf", text: $kerfText)
            KerfWarning(text: kerfText)
            Picker("Blade tilts", selection: $tilt) {
                ForEach(BladeTilt.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Stock")
        }
    }

    @ViewBuilder private var resultSection: some View {
        switch method {
        case .split:
            if let r = split {
                Section {
                    BigResult(title: "Fence setting",
                              value: len(r.fence),
                              detail: unit.detail(r.fence, precision: precision))
                    if solveFrom == .cleat {
                        ResultRow(label: "Rip board to", value: len(r.boardWidth))
                    }
                    ResultRow(label: "Each cleat, wide face", value: len(r.longFace))
                    ResultRow(label: "Each cleat, narrow face", value: len(r.shortFace))
                    CleatDiagram(boardWidth: r.boardWidth, thickness: r.verticalCut,
                                 fence: r.fence, kerf: kerf, tilt: tilt)
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    warnings(onTable: r.fencePieceOnTable)
                } header: {
                    Text("Result")
                } footer: {
                    Text("One cut makes two identical cleats. Flip one end for end to pair them.")
                }
            } else {
                invalidSection
            }
        case .edge:
            if let r = edge, let s = unit.inches(stripText), let t = thickness {
                Section {
                    BigResult(title: "Fence setting",
                              value: len(r.fence),
                              detail: unit.detail(r.fence, precision: precision))
                    ResultRow(label: "Wide face", value: len(r.longFace))
                    ResultRow(label: "Narrow face", value: len(r.shortFace))
                    CleatDiagram(boardWidth: s, thickness: t, fence: r.fence, kerf: kerf, tilt: tilt)
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    warnings(onTable: r.fencePieceOnTable)
                } header: {
                    Text("Result")
                } footer: {
                    Text("The kerf lands right at the far corner, so the strip keeps its full width on one face. Kerf does not change this setting.")
                }
            } else {
                invalidSection
            }
        }
    }

    private var invalidSection: some View {
        Section {
            Callout(kind: .warning, text: "Check the inputs. The board has to be wider than its thickness plus the kerf.")
        }
    }

    @ViewBuilder private func warnings(onTable: Double) -> some View {
        if tilt == .towardFence {
            Callout(kind: .warning, text: "With the blade tilted toward the fence, the fence side piece is trapped under the blade. Move the fence to the other side of the blade if your saw allows it.")
        }
        if onTable < 1 {
            Callout(kind: .warning, text: "The piece between fence and blade is under \(minPiece) at the table. Use a push block and keep your hand off the blade side.")
        }
    }

    private var testCutSection: some View {
        Section {
            MeasureField(label: "Fence piece, wide face", text: $testFenceText)
            MeasureField(label: "Offcut, wide face", text: $testOffcutText)
            if let f = unit.inches(testFenceText), let o = unit.inches(testOffcutText) {
                let move = CleatSplit.fenceCorrection(fencePieceLongFace: f, offcutLongFace: o)
                if abs(move) < 1.0 / 128 {
                    Callout(kind: .info, text: unit == .imperial
                            ? "Within 1/128\". Leave the fence where it is."
                            : "Within 0.2 mm. Leave the fence where it is.")
                } else {
                    Callout(kind: .info, text: "Move the fence \(correction(abs(move))) \(move > 0 ? "away from" : "toward") the blade.")
                }
            }
        } header: {
            Text("Test cut check")
        } footer: {
            Text("Rip a scrap at the setting above, measure both wide faces, and this tells you how far to move the fence so the two cleats match.")
        }
    }
}

/// Cross section of the cut: fence on the left, table along the bottom, kerf shaded.
struct CleatDiagram: View {
    let boardWidth: Double
    let thickness: Double
    let fence: Double
    let kerf: Double
    let tilt: BladeTilt

    var body: some View {
        Canvas { ctx, size in
            let margin: CGFloat = 12
            let fenceW: CGFloat = 10
            let usableW = size.width - 2 * margin - fenceW
            let usableH = size.height - 2 * margin - 14
            guard boardWidth > 0, thickness > 0, usableW > 0, usableH > 0 else { return }
            let scale = min(usableW / boardWidth, usableH / thickness)
            let left = margin + fenceW
            let bottom = size.height - margin - 14

            func pt(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: left + CGFloat(x) * scale, y: bottom - CGFloat(y) * scale)
            }

            // Table
            var table = Path()
            table.move(to: CGPoint(x: margin / 2, y: bottom))
            table.addLine(to: CGPoint(x: size.width - margin / 2, y: bottom))
            ctx.stroke(table, with: .color(.secondary), lineWidth: 1)

            // Fence
            let fenceRect = CGRect(x: margin, y: bottom - CGFloat(thickness) * scale - 8,
                                   width: fenceW, height: CGFloat(thickness) * scale + 8)
            ctx.fill(Path(fenceRect), with: .color(.gray))

            // Board
            var board = Path()
            board.addRect(CGRect(origin: pt(0, thickness),
                                 size: CGSize(width: CGFloat(boardWidth) * scale, height: CGFloat(thickness) * scale)))
            ctx.fill(board, with: .color(Color(red: 0.86, green: 0.72, blue: 0.52)))

            // Kerf, clipped to the board
            let kh = BevelRip.horizontalKerf(kerf)
            let r = BevelRip.run(thickness)
            let s: Double = tilt == .awayFromFence ? 1 : -1
            var cut = Path()
            cut.move(to: pt(fence, 0))
            cut.addLine(to: pt(fence + kh, 0))
            cut.addLine(to: pt(fence + kh + s * r, thickness))
            cut.addLine(to: pt(fence + s * r, thickness))
            cut.closeSubpath()
            var clipped = ctx
            clipped.clip(to: board)
            clipped.fill(cut, with: .color(.red.opacity(0.75)))

            ctx.stroke(board, with: .color(.brown), lineWidth: 1)

            // Fence dimension under the table
            let y = bottom + 8
            var dim = Path()
            dim.move(to: CGPoint(x: left, y: y))
            dim.addLine(to: CGPoint(x: left + CGFloat(fence) * scale, y: y))
            ctx.stroke(dim, with: .color(.accentColor), lineWidth: 1.5)
            ctx.draw(Text("fence").font(.caption2).foregroundColor(.accentColor),
                     at: CGPoint(x: left + CGFloat(fence) * scale / 2, y: y + 7))
        }
        .accessibilityLabel("Cross section of the bevel cut")
    }
}
