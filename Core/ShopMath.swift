import Foundation

// All lengths in inches, all angles in degrees unless noted.

private func rad(_ deg: Double) -> Double { deg * .pi / 180 }
private func deg(_ rad: Double) -> Double { rad * 180 / .pi }

// MARK: - French cleats on the table saw

enum BladeTilt: String, CaseIterable, Identifiable, Codable {
    case awayFromFence
    case towardFence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awayFromFence: return "Away from fence"
        case .towardFence: return "Toward fence"
        }
    }
}

/// Geometry of one bevel rip. The fence distance is measured at the table surface from the
/// fence to the fence side of the kerf (the tooth nearest the fence where it leaves the throat plate).
///
/// Coordinates: x is distance from the fence, y is height above the table.
/// The fence side of the kerf is the line x = fence ± y·tan(bevel).
/// Kerf width k is measured across the blade, so on the table it spans k / cos(bevel).
struct BevelRip {
    static func horizontalKerf(_ kerf: Double, bevel: Double = 45) -> Double {
        kerf / cos(rad(bevel))
    }

    static func run(_ thickness: Double, bevel: Double = 45) -> Double {
        thickness * tan(rad(bevel))
    }
}

struct CleatSplit {
    /// Fence to the fence side of the kerf, at the table.
    let fence: Double
    /// Wide face of each cleat (the face that goes against the wall or cabinet).
    let longFace: Double
    /// Narrow face of each cleat.
    let shortFace: Double
    /// Board width this was solved for.
    let boardWidth: Double
    /// Width of the fence side piece where it touches the table. Small values mean hands near the blade.
    let fencePieceOnTable: Double
    /// Height of the blade needed, measured straight up from the table, before tooth clearance.
    let verticalCut: Double

    /// Rip one board into two identical cleats with a single bevel cut.
    static func fromBoard(width w: Double, thickness t: Double, kerf k: Double,
                          tilt: BladeTilt, bevel: Double = 45) -> CleatSplit? {
        let kh = BevelRip.horizontalKerf(k, bevel: bevel)
        let r = BevelRip.run(t, bevel: bevel)
        guard w > 0, t > 0, k >= 0, w > r + kh else { return nil }
        let longFace = (w + r - kh) / 2
        let fence: Double
        let onTable: Double
        switch tilt {
        case .awayFromFence:
            // Fence piece: a at the table, a + r on top. Offcut: w − a − kh at the table.
            fence = (w - r - kh) / 2
            onTable = fence
        case .towardFence:
            // Fence piece: a at the table, a − r on top. Offcut: w − a − kh + r on top.
            fence = (w + r - kh) / 2
            onTable = fence
        }
        return CleatSplit(fence: fence, longFace: longFace, shortFace: longFace - r,
                          boardWidth: w, fencePieceOnTable: onTable, verticalCut: t)
    }

    /// Board width needed for a target cleat width (wide face).
    static func fromCleat(longFace lw: Double, thickness t: Double, kerf k: Double,
                          tilt: BladeTilt, bevel: Double = 45) -> CleatSplit? {
        let kh = BevelRip.horizontalKerf(k, bevel: bevel)
        let r = BevelRip.run(t, bevel: bevel)
        guard lw > r, t > 0, k >= 0 else { return nil }
        return fromBoard(width: 2 * lw - r + kh, thickness: t, kerf: k, tilt: tilt, bevel: bevel)
    }

    /// After a test cut: how far to move the fence so both cleats match.
    /// Positive means move the fence away from the blade (widen the fence piece).
    static func fenceCorrection(fencePieceLongFace: Double, offcutLongFace: Double) -> Double {
        (offcutLongFace - fencePieceLongFace) / 2
    }
}

struct CleatEdgeBevel {
    let fence: Double
    let longFace: Double
    let shortFace: Double
    let fencePieceOnTable: Double

    /// Bevel one edge of a strip already ripped to width. The strip rides against the fence and keeps
    /// its full width on one face; the corner beyond the blade falls away as a small triangle.
    static func make(stripWidth s: Double, thickness t: Double, tilt: BladeTilt,
                     bevel: Double = 45) -> CleatEdgeBevel? {
        let r = BevelRip.run(t, bevel: bevel)
        guard s > r, t > 0 else { return nil }
        switch tilt {
        case .awayFromFence:
            // Wide face ends up on top: a + r = s.
            return CleatEdgeBevel(fence: s - r, longFace: s, shortFace: s - r, fencePieceOnTable: s - r)
        case .towardFence:
            // Wide face is on the table: a = s.
            return CleatEdgeBevel(fence: s, longFace: s, shortFace: s - r, fencePieceOnTable: s)
        }
    }
}

// MARK: - Board feet

enum BoardFeet {
    static func of(thickness t: Double, width w: Double, length l: Double, quantity q: Int = 1) -> Double {
        t * w * l / 144 * Double(q)
    }
}

struct LumberItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var thickness: Double
    var width: Double
    var length: Double
    var quantity: Int
    var pricePerBoardFoot: Double

    var boardFeet: Double {
        BoardFeet.of(thickness: thickness, width: width, length: length, quantity: quantity)
    }

    var cost: Double { boardFeet * pricePerBoardFoot }
}

struct LumberTotals: Equatable {
    let boardFeet: Double
    let boardFeetWithWaste: Double
    let cost: Double
    let costWithWaste: Double

    static func of(_ items: [LumberItem], wastePercent: Double) -> LumberTotals {
        let bf = items.reduce(0) { $0 + $1.boardFeet }
        let cost = items.reduce(0) { $0 + $1.cost }
        let m = 1 + max(0, wastePercent) / 100
        return LumberTotals(boardFeet: bf, boardFeetWithWaste: bf * m, cost: cost, costWithWaste: cost * m)
    }
}

// MARK: - Miter and bevel angles

struct SawSettings: Equatable {
    /// Miter saw table angle from the 0° (square) detent.
    let miter: Double
    /// Blade tilt from 0° (vertical).
    let bevel: Double
}

enum Angles {
    /// Flat frame with n sides (picture frame, octagon mirror): each end is a plain miter.
    static func flatFrame(sides n: Int) -> SawSettings? {
        guard n >= 3 else { return nil }
        return SawSettings(miter: 180 / Double(n), bevel: 0)
    }

    /// Box with straight (vertical) sides and mitered corners, board lying flat on the saw: a plain bevel.
    static func straightBox(sides n: Int) -> SawSettings? {
        guard n >= 3 else { return nil }
        return SawSettings(miter: 0, bevel: 180 / Double(n))
    }

    /// Box or planter with n sides, each tilted outward by `tilt` degrees from vertical, board lying flat.
    /// bevel = asin(sin(180/n) · cos(tilt)), miter = atan(tan(180/n) · sin(tilt)).
    static func compound(sides n: Int, tiltFromVertical tilt: Double) -> SawSettings? {
        guard n >= 3, tilt >= 0, tilt < 90 else { return nil }
        let a = rad(180 / Double(n))
        let t = rad(tilt)
        let bevel = deg(asin(sin(a) * cos(t)))
        let miter = deg(atan(tan(a) * sin(t)))
        return SawSettings(miter: miter, bevel: bevel)
    }

    /// Edge length of a regular n-gon measured flat to flat across the outside.
    /// For a frame of stock width w, the inside edge is the same formula with (across − 2w).
    static func edgeLength(acrossFlats d: Double, sides n: Int) -> Double {
        d * tan(.pi / Double(n))
    }
}

// MARK: - End grain cutting board planner

struct EndGrainInput {
    var boardLength: Double        // along each slice: strips × strip width
    var boardWidth: Double         // slices × slice face
    var boardThickness: Double     // final, after flattening
    var stripWidth: Double         // each strip's width across the first glue-up
    var panelThickness: Double     // first glue-up thickness as glued (strip height)
    var firstFlatten: Double       // removed flattening the first panel
    var finalFlatten: Double       // removed flattening the end grain board
    var edgeTrim: Double           // trimmed off the edges of each glue-up, total
    var endTrim: Double            // squaring cut on the panel end before slicing
    var kerf: Double
    var yieldPercent: Double
}

struct EndGrainPlan {
    let strips: Int
    let stripWidth: Double
    let stripHeight: Double
    let finishedThickness: Double
    let stripLength: Double
    let slices: Int
    let sliceWidth: Double         // crosscut setting for each slice
    let sliceFace: Double          // each slice's contribution to board width
    let panelWidth: Double
    let panelLength: Double
    let asGluedLength: Double
    let asGluedWidth: Double
    let finishedLength: Double
    let finishedWidth: Double
    let netBoardFeet: Double
    let roughBoardFeet: Double

    static func make(_ i: EndGrainInput) -> EndGrainPlan? {
        guard i.boardLength > 0, i.boardWidth > 0, i.boardThickness > 0,
              i.stripWidth > 0, i.panelThickness > i.firstFlatten,
              i.firstFlatten >= 0, i.finalFlatten >= 0, i.edgeTrim >= 0, i.endTrim >= 0,
              i.kerf >= 0, i.yieldPercent > 0, i.yieldPercent <= 100 else { return nil }

        let strips = Int(ceil((i.boardLength + i.edgeTrim) / i.stripWidth - 1e-9))
        let sliceFace = i.panelThickness - i.firstFlatten
        let slices = Int(ceil((i.boardWidth + i.edgeTrim) / sliceFace - 1e-9))
        let sliceWidth = i.boardThickness + i.finalFlatten
        let panelLength = i.endTrim + Double(slices) * (sliceWidth + i.kerf)
        let panelWidth = Double(strips) * i.stripWidth
        let asGluedWidth = Double(slices) * sliceFace
        let net = BoardFeet.of(thickness: i.panelThickness, width: panelWidth, length: panelLength)
        return EndGrainPlan(
            strips: strips,
            stripWidth: i.stripWidth,
            stripHeight: i.panelThickness,
            finishedThickness: i.boardThickness,
            stripLength: panelLength,
            slices: slices,
            sliceWidth: sliceWidth,
            sliceFace: sliceFace,
            panelWidth: panelWidth,
            panelLength: panelLength,
            asGluedLength: panelWidth,
            asGluedWidth: asGluedWidth,
            finishedLength: panelWidth - i.edgeTrim,
            finishedWidth: asGluedWidth - i.edgeTrim,
            netBoardFeet: net,
            roughBoardFeet: net / (i.yieldPercent / 100)
        )
    }
}
