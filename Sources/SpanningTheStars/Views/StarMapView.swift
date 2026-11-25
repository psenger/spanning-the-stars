import SwiftUI
import AppKit
import StarsCore

/// The galaxy map: backdrop, lanes drawn as slots, Star System markers and names.
/// The backdrop fills the whole frame (scaled to fill, clipped). The 1000x620 map space is scaled
/// uniformly to fit and centered; hover and taps are read in that centered space, so hit testing
/// follows the scale and offset at any frame size.
///
/// The map is fixed for the life of the view, so its layout is computed once and held in state.
/// Mouse movement only updates `HoverPoint`, which the tooltip alone reads; the lane Canvas
/// redraws only when the hovered lane changes.
struct StarMapView: View {
    let map: GalaxyMap
    let state: GameState
    let hazards: Bool
    var highlight: Set<Int> = []
    /// Star System ids ringed in brass, for example the ends of the contracts being chosen.
    var highlightSystems: Set<String> = []
    var onSelectLane: (Int) -> Void = { _ in }

    @State private var layoutHolder = LayoutHolder()
    @State private var hovered: Int?
    @State private var pointer = HoverPoint()

    var body: some View {
        let layout = layoutHolder.layout(for: map)
        GeometryReader { geo in
            let s = min(geo.size.width / StarMapLayout.space.width, geo.size.height / StarMapLayout.space.height)
            let size = CGSize(width: StarMapLayout.space.width * s, height: StarMapLayout.space.height * s)
            ZStack {
                ArtImage(.mapBackdrop)
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                // A light scrim keeps lanes the dominant layer over bright nebula art.
                Color.black.opacity(0.22)
                mapContent(layout: layout, scale: s, size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
        }
    }

    /// Everything placed in map space, in a frame of exactly `size` (the map at scale `s`).
    private func mapContent(layout: StarMapLayout, scale s: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            SwiftUI.Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                LaneRenderer(map: map, state: state, hazards: hazards, layout: layout,
                             highlight: highlight, hovered: hovered).draw(in: &ctx)
            }
            .frame(width: size.width, height: size.height)

            if hazards {
                ForEach(map.lanes.filter { $0.hazard != .none }) { lane in
                    hazardGlyph(lane, layout: layout, scale: s)
                }
            }

            ForEach(map.systems.filter { highlightSystems.contains($0.id) }) { sys in
                Circle()
                    .strokeBorder(Palette.brass, lineWidth: 2.2 * s)
                    .background(Circle().fill(Palette.brass.opacity(0.18)))
                    .frame(width: StarMapLayout.starSize * 1.9 * s, height: StarMapLayout.starSize * 1.9 * s)
                    .shadow(color: Palette.brass.opacity(0.9), radius: 6 * s)
                    .position(x: sys.x * s, y: sys.y * s)
                    .allowsHitTesting(false)
            }

            ForEach(map.systems) { sys in
                ArtImage(.star(sys.region))
                    .frame(width: StarMapLayout.starSize * s, height: StarMapLayout.starSize * s)
                    .position(x: sys.x * s, y: sys.y * s)
            }

            ForEach(map.systems) { sys in
                if let label = layout.labels[sys.id] {
                    SystemLabel(text: label.text, alignment: label.alignment, scale: s)
                        .position(x: label.rect.midX * s, y: label.rect.midY * s)
                }
            }

            if let id = hovered {
                FollowingTooltip(pointer: pointer, bounds: size,
                                 tooltip: LaneTooltip(map: map, state: state, lane: map.lane(id), hazards: hazards))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        // Locations here are local to the centered map frame, so dividing by `s` gives map space.
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                pointer.location = p
                let near = layout.lane(near: CGPoint(x: p.x / s, y: p.y / s))
                if near != hovered { hovered = near }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
        .onTapGesture { p in
            if let id = layout.lane(near: CGPoint(x: p.x / s, y: p.y / s)) { onSelectLane(id) }
        }
    }

    private func hazardGlyph(_ lane: Lane, layout: StarMapLayout, scale s: CGFloat) -> some View {
        let mid = layout.midpoint(lane.id)
        let d = StarMapLayout.glyphSize * s
        return ArtImage(lane.hazard == .spectrum ? .glyphSpectrum : .glyphGravity)
            .frame(width: d, height: d)
            .padding(1.5 * s)
            .background(Circle().fill(Color.black.opacity(0.75)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6 * s))
            .position(x: mid.x * s, y: mid.y * s)
            .allowsHitTesting(false)
    }
}

// MARK: - Labels and tooltip

private struct SystemLabel: View {
    let text: String
    let alignment: TextAlignment
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: StarMapLayout.labelFontSize * scale, weight: .semibold))
            .multilineTextAlignment(alignment)
            .lineSpacing(0)
            .foregroundStyle(Palette.text)
            .fixedSize()
            // Stacked tight shadows make a dark halo that reads on any backdrop.
            .shadow(color: .black, radius: 0.8 * scale)
            .shadow(color: .black, radius: 1.2 * scale)
            .shadow(color: .black.opacity(0.7), radius: 3 * scale)
            .allowsHitTesting(false)
    }
}

/// The last pointer position over the map. Only `FollowingTooltip` reads it.
@MainActor @Observable private final class HoverPoint {
    var location: CGPoint = .zero
}

/// Computes the map layout on first use and keeps it for the life of the owning view.
@MainActor private final class LayoutHolder {
    private var layout: StarMapLayout?

    func layout(for map: GalaxyMap) -> StarMapLayout {
        if let layout { return layout }
        let made = StarMapLayout.cached(for: map)
        layout = made
        return made
    }
}

/// Places the tooltip beside the pointer, flipping left or up near the map edges.
private struct FollowingTooltip: View {
    let pointer: HoverPoint
    let bounds: CGSize
    let tooltip: LaneTooltip

    var body: some View {
        let pt = pointer.location
        tooltip
            .alignmentGuide(.leading) { d in
                pt.x + 16 + d.width > bounds.width ? d.width + 12 - pt.x : -(pt.x + 16)
            }
            .alignmentGuide(.top) { d in
                pt.y + 18 + d.height > bounds.height ? d.height + 10 - pt.y : -(pt.y + 18)
            }
            .allowsHitTesting(false)
    }
}

private struct LaneTooltip: View {
    let map: GalaxyMap
    let state: GameState
    let lane: Lane
    let hazards: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(map.system(lane.a).name) to \(map.system(lane.b).name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LaneRenderer.fill(lane.color))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 16, height: 7)
                Text("Length \(lane.length), \(lanePoints(lane.length)) Concord Standing")
                    .foregroundStyle(Palette.dimText)
            }
            Text("Cost: \(StarMapView.costText(lane, hazards: hazards))")
                .foregroundStyle(Palette.text)
            if hazards && lane.hazard == .spectrum {
                Text("Spectrum Lane: each slot needs a different resource")
                    .foregroundStyle(Palette.dimText)
            } else if hazards && lane.hazard == .gravityWell {
                Text("Gravity Well: one card fewer, one Anchor Beacon lost")
                    .foregroundStyle(Palette.dimText)
            }
            if let seat = state.laneOwner[lane.id], state.players.indices.contains(seat) {
                Text("Anchored by \(state.players[seat].house.displayName)")
                    .foregroundStyle(Palette.brass)
            } else if LaneRenderer.showsClosed(lane, state) {
                Text("Closed: its twin is anchored")
                    .foregroundStyle(Palette.dimText)
            }
        }
        .font(.system(size: 12))
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Palette.hex(0x0B1024, opacity: 0.94), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.brass.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
    }
}

extension StarMapView {
    /// Card cost of a lane, e.g. "3 Plasma Fuel" or "3 of any one resource".
    static func costText(_ lane: Lane, hazards: Bool) -> String {
        if hazards && lane.hazard == .spectrum {
            return "\(lane.length) different resources"
        }
        let cards = hazards && lane.hazard == .gravityWell ? lane.length - 1 : lane.length
        let base: String
        switch lane.color {
        case .color(let c): base = "\(cards) \(c.resourceName)"
        case .open: base = "\(cards) of any one resource"
        }
        if hazards && lane.hazard == .gravityWell {
            return "\(base) and \(beaconCost(lane, hazards: true)) Anchor Beacons"
        }
        return base
    }
}

// MARK: - Lane drawing

private struct LaneRenderer {
    let map: GalaxyMap
    let state: GameState
    let hazards: Bool
    let layout: StarMapLayout
    let highlight: Set<Int>
    let hovered: Int?

    static let openGray = Palette.hex(0x8E95A6)

    static func fill(_ c: LaneColor) -> Color {
        switch c {
        case .color(let r): Palette.resource(r)
        case .open: openGray
        }
    }

    /// An open lane the engine treats as closed; an anchored lane is drawn as anchored instead.
    static func showsClosed(_ lane: Lane, _ state: GameState) -> Bool {
        state.laneOwner[lane.id] == nil && isClosed(lane, in: state)
    }

    private static let rainbow = Gradient(colors: [
        Palette.hex(0xFF4D4D), Palette.hex(0xFFA62B), Palette.hex(0xFFE74C),
        Palette.hex(0x4CD964), Palette.hex(0x3FA7F5), Palette.hex(0xB26BFF),
    ])

    func draw(in ctx: inout GraphicsContext) {
        let th = StarMapLayout.slotThickness

        // Pass 1: dark underlay so every lane separates from the backdrop.
        for lane in map.lanes {
            let seg = layout.segment(lane.id)
            var line = Path()
            line.move(to: seg.a)
            line.addLine(to: seg.b)
            let closed = Self.showsClosed(lane, state)
            ctx.stroke(line, with: .color(.black.opacity(closed ? 0.25 : 0.55)),
                       style: StrokeStyle(lineWidth: th + 3.5, lineCap: .round))
        }

        // Pass 2: hover and highlight glows.
        for lane in map.lanes where lane.id == hovered || highlight.contains(lane.id) {
            let seg = layout.segment(lane.id)
            var line = Path()
            line.move(to: seg.a)
            line.addLine(to: seg.b)
            let color = lane.id == hovered ? Color.white : Palette.brass
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.stroke(line, with: .color(color.opacity(0.95)),
                             style: StrokeStyle(lineWidth: th + 6, lineCap: .round))
            }
            ctx.stroke(line, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: th + 3, lineCap: .round))
        }

        // Pass 3: slots.
        for lane in map.lanes {
            drawLane(lane, in: &ctx)
        }
    }

    private func drawLane(_ lane: Lane, in ctx: inout GraphicsContext) {
        let th = StarMapLayout.slotThickness
        let seg = layout.segment(lane.id)
        let dx = seg.b.x - seg.a.x, dy = seg.b.y - seg.a.y
        let length = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let n = CGFloat(lane.length)
        let gap = StarMapLayout.slotGap
        let slotLength = (length - gap * (n - 1)) / n

        func transform(at k: Int) -> CGAffineTransform {
            let t = (slotLength / 2 + CGFloat(k) * (slotLength + gap)) / length
            return CGAffineTransform(translationX: seg.a.x + dx * t, y: seg.a.y + dy * t).rotated(by: angle)
        }
        func slot(_ k: Int, thickness: CGFloat, inset: CGFloat = 0) -> Path {
            let r = CGRect(x: -slotLength / 2, y: -thickness / 2, width: slotLength, height: thickness)
                .insetBy(dx: inset, dy: inset)
            return Path(roundedRect: r, cornerRadius: r.height * 0.32).applying(transform(at: k))
        }

        let owner = state.laneOwner[lane.id].flatMap { state.players.indices.contains($0) ? state.players[$0].house : nil }
        let closed = Self.showsClosed(lane, state)
        let fill = Self.fill(lane.color)

        if hazards && lane.hazard == .spectrum && !closed {
            let r = CGRect(x: -length / 2 - 2.2, y: -th / 2 - 2.2, width: length + 4.4, height: th + 4.4)
            let mid = CGAffineTransform(translationX: (seg.a.x + seg.b.x) / 2, y: (seg.a.y + seg.b.y) / 2)
                .rotated(by: angle)
            let ring = Path(roundedRect: r, cornerRadius: r.height / 2).applying(mid)
            ctx.stroke(ring, with: .linearGradient(Self.rainbow, startPoint: seg.a, endPoint: seg.b), lineWidth: 1.5)
        }

        if let owner {
            // Anchored lanes glow in the House color, so they read apart from unclaimed slots.
            var line = Path()
            line.move(to: seg.a)
            line.addLine(to: seg.b)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.5))
                layer.stroke(line, with: .color(Palette.houseRim(owner).opacity(0.85)),
                             style: StrokeStyle(lineWidth: th + 4, lineCap: .round))
            }
        }

        for k in 0..<lane.length {
            if let owner {
                let core = Path { p in
                    let r: CGFloat = 2.3
                    p.move(to: CGPoint(x: 0, y: -r))
                    p.addLine(to: CGPoint(x: r, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: r))
                    p.addLine(to: CGPoint(x: -r, y: 0))
                    p.closeSubpath()
                }.applying(transform(at: k))
                drawBeacon(slot(k, thickness: th + 2), inner: slot(k, thickness: th + 2, inset: 1.2),
                           core: core, house: owner, in: &ctx)
            } else if closed {
                let p = slot(k, thickness: th)
                ctx.fill(p, with: .color(fill.opacity(0.18)))
                ctx.stroke(p, with: .color(fill.mix(with: .white, by: 0.2).opacity(0.55)),
                           style: StrokeStyle(lineWidth: 0.8, dash: [2.2, 1.6]))
            } else {
                let p = slot(k, thickness: th)
                ctx.fill(p, with: .color(fill))
                let edge: Color = lane.color == .color(.black) ? Palette.hex(0x9AA0B4) : .black.opacity(0.8)
                ctx.stroke(p, with: .color(edge), lineWidth: 0.9)
            }
        }
    }

    /// An anchored slot: the House color with a light inner highlight and a bright beacon core.
    private func drawBeacon(_ p: Path, inner: Path, core: Path, house: House, in ctx: inout GraphicsContext) {
        let base = Palette.house(house)
        let pale = house == .paleFleet
        let light = pale ? Palette.houseRim(house) : base.mix(with: .white, by: 0.7)
        ctx.fill(p, with: .color(base))
        ctx.stroke(p, with: .color(pale ? light : .black.opacity(0.9)), lineWidth: 0.9)
        ctx.stroke(inner, with: .color(light.opacity(pale ? 0.35 : 0.75)), lineWidth: 0.7)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: light, radius: 1.5))
            layer.fill(core, with: .color(light))
        }
    }
}

// MARK: - Layout

/// Map-space geometry for one `GalaxyMap`: trimmed lane segments (twins offset) and label rectangles.
struct StarMapLayout {
    static let space = CGSize(width: 1000, height: 620)
    static let starSize: CGFloat = 21
    static let slotThickness: CGFloat = 6
    static let slotGap: CGFloat = 2.4
    /// Distance between the center lines of two twin lanes.
    static let twinSpacing: CGFloat = 7
    static let glyphSize: CGFloat = 11
    static let labelFontSize: CGFloat = 11.5
    static let hitDistance: CGFloat = 10

    struct Segment { var a: CGPoint; var b: CGPoint }
    /// A placed System name: its map-space box, the text (possibly on two lines) and alignment.
    struct MapLabel { var rect: CGRect; var text: String; var alignment: TextAlignment }

    let segments: [Int: Segment]
    let labels: [String: MapLabel]

    func segment(_ id: Int) -> Segment { segments[id]! }

    func midpoint(_ id: Int) -> CGPoint {
        let s = segment(id)
        return CGPoint(x: (s.a.x + s.b.x) / 2, y: (s.a.y + s.b.y) / 2)
    }

    /// The nearest lane closer than `hitDistance` map units, if any.
    func lane(near p: CGPoint) -> Int? {
        var best: (id: Int, d: Double)?
        for (id, s) in segments {
            let d = distanceToSegment((p.x, p.y), (s.a.x, s.a.y), (s.b.x, s.b.y))
            if d < Self.hitDistance, d < best?.d ?? .infinity { best = (id, d) }
        }
        return best?.id
    }

    @MainActor private static var cache: [String: StarMapLayout] = [:]

    @MainActor static func cached(for map: GalaxyMap) -> StarMapLayout {
        let key = map.systems.map { "\($0.id)@\($0.x),\($0.y)" }.joined(separator: ";")
            + "|" + map.lanes.map { "\($0.a)-\($0.b)" }.joined(separator: ";")
        if let hit = cache[key] { return hit }
        let layout = StarMapLayout(map: map)
        cache[key] = layout
        return layout
    }

    init(map: GalaxyMap) {
        var points: [String: CGPoint] = [:]
        for s in map.systems { points[s.id] = CGPoint(x: s.x, y: s.y) }

        var segs: [Int: Segment] = [:]
        let trim = Self.starSize / 2 + 3
        for lane in map.lanes {
            // Canonical direction so both twins share one normal.
            let (ida, idb) = lane.a < lane.b ? (lane.a, lane.b) : (lane.b, lane.a)
            let a = points[ida]!, b = points[idb]!
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            let ux = dx / len, uy = dy / len
            var off: CGFloat = 0
            if let twin = lane.twinID { off = (lane.id < twin ? 0.5 : -0.5) * Self.twinSpacing }
            let nx = -uy * off, ny = ux * off
            segs[lane.id] = Segment(a: CGPoint(x: a.x + ux * trim + nx, y: a.y + uy * trim + ny),
                                    b: CGPoint(x: b.x - ux * trim + nx, y: b.y - uy * trim + ny))
        }
        segments = segs
        labels = Self.placeLabels(map: map, points: points, segments: segs)
    }

    /// Greedy label placement: try sixteen positions around each marker, on one line and (for
    /// multi-word names) on two, and keep the one that stays inside the map and covers the fewest
    /// lane samples, markers, hazard glyphs and earlier labels.
    private static func placeLabels(map: GalaxyMap, points: [String: CGPoint],
                                    segments: [Int: Segment]) -> [String: MapLabel] {
        let font = NSFont.systemFont(ofSize: labelFontSize, weight: .semibold)
        let bounds = CGRect(origin: .zero, size: space).insetBy(dx: 4, dy: 4)
        let lineHeight = labelFontSize * 1.22

        var samples: [CGPoint] = []
        for s in segments.values {
            let len = hypot(s.b.x - s.a.x, s.b.y - s.a.y)
            let n = max(1, Int(len / 2))
            for i in 0...n {
                let t = CGFloat(i) / CGFloat(n)
                samples.append(CGPoint(x: s.a.x + (s.b.x - s.a.x) * t, y: s.a.y + (s.b.y - s.a.y) * t))
            }
        }
        let glyphs = map.lanes.filter { $0.hazard != .none }.map { lane -> CGPoint in
            let s = segments[lane.id]!
            return CGPoint(x: (s.a.x + s.b.x) / 2, y: (s.a.y + s.b.y) / 2)
        }

        struct Candidate { var label: MapLabel; var cost: Double }

        func width(_ text: String) -> CGFloat {
            text.split(separator: "\n").map {
                ceil((String($0) as NSString).size(withAttributes: [.font: font]).width)
            }.max()! + 2
        }

        /// The name on one line, plus a two-line form split at the space nearest the middle.
        func forms(_ name: String) -> [(text: String, lines: Int, pref: Double)] {
            var result = [(name, 1, 0.0)]
            let spaces = name.indices.filter { name[$0] == " " }
            let middle = name.count / 2
            if let split = spaces.min(by: {
                abs(name.distance(from: name.startIndex, to: $0) - middle)
                    < abs(name.distance(from: name.startIndex, to: $1) - middle)
            }) {
                var two = name
                two.replaceSubrange(split...split, with: "\n")
                result.append((two, 2, 6))
            }
            return result
        }

        func candidates(for sys: StarSystem) -> [Candidate] {
            let c = points[sys.id]!
            let r = starSize / 2 + 2
            let d = r * 0.62
            return forms(sys.name).flatMap { text, lines, formPref -> [Candidate] in
                let w = width(text)
                let h = lineHeight * CGFloat(lines) + 1
                let sx = r * 0.3, sy = min(h, lineHeight) * 0.55
                let options: [(CGFloat, CGFloat, Double, TextAlignment)] = [
                    (c.x + r, c.y - h / 2, 0, .leading),                 // east
                    (c.x - r - w, c.y - h / 2, 0.4, .trailing),          // west
                    (c.x - w / 2, c.y + r - 1, 0.8, .center),            // south
                    (c.x - w / 2, c.y - r - h + 1, 0.8, .center),        // north
                    (c.x + r, c.y - h / 2 - sy, 1, .leading),            // east, raised
                    (c.x + r, c.y - h / 2 + sy, 1, .leading),            // east, lowered
                    (c.x - r - w, c.y - h / 2 - sy, 1.2, .trailing),     // west, raised
                    (c.x - r - w, c.y - h / 2 + sy, 1.2, .trailing),     // west, lowered
                    (c.x - sx, c.y + r - 1, 1.1, .leading),              // south, trailing right
                    (c.x + sx - w, c.y + r - 1, 1.1, .trailing),         // south, trailing left
                    (c.x - sx, c.y - r - h + 1, 1.1, .leading),          // north, trailing right
                    (c.x + sx - w, c.y - r - h + 1, 1.1, .trailing),     // north, trailing left
                    (c.x + d, c.y - d - h + 2, 1.4, .leading),           // north-east
                    (c.x + d, c.y + d - 2, 1.4, .leading),               // south-east
                    (c.x - d - w, c.y - d - h + 2, 1.6, .trailing),      // north-west
                    (c.x - d - w, c.y + d - 2, 1.6, .trailing),          // south-west
                ]
                return options.map { x, y, pref, align in
                    let rect = CGRect(x: x, y: y, width: w, height: h)
                    var cost = pref + formPref
                    if !bounds.contains(rect) { cost += 10_000 }
                    // A lane through the text costs far more than one grazing the halo margin.
                    let core = rect.insetBy(dx: -slotThickness / 2, dy: -slotThickness / 2)
                    let near = rect.insetBy(dx: -(slotThickness / 2 + 3.5), dy: -(slotThickness / 2 + 3.5))
                    for p in samples where near.contains(p) { cost += core.contains(p) ? 4 : 1 }
                    for other in map.systems where other.id != sys.id {
                        if rect.insetBy(dx: -starSize / 2, dy: -starSize / 2).contains(points[other.id]!) { cost += 60 }
                    }
                    for g in glyphs where rect.insetBy(dx: -glyphSize / 2 - 2, dy: -glyphSize / 2 - 2).contains(g) {
                        cost += 25
                    }
                    return Candidate(label: MapLabel(rect: rect, text: text, alignment: align), cost: cost)
                }
            }
        }

        let all = map.systems.map { ($0, candidates(for: $0)) }
        // Most constrained systems choose first.
        let order = all.sorted {
            ($0.1.map(\.cost).min() ?? 0) > ($1.1.map(\.cost).min() ?? 0)
        }
        var placed: [String: MapLabel] = [:]
        for (sys, cands) in order {
            let best = cands.min { a, b in
                total(a, placed) < total(b, placed)
            }!
            placed[sys.id] = best.label
        }
        return placed

        func total(_ c: Candidate, _ placed: [String: MapLabel]) -> Double {
            c.cost + Double(placed.values.filter { $0.rect.insetBy(dx: -2, dy: -1).intersects(c.label.rect) }.count) * 200
        }
    }
}

// MARK: - Debug route and preview

#if DEBUG
/// Debug screen for the map with sample anchored lanes and hazards on. Launch with `-map`.
struct StarMapDebugView: View {
    @State private var selected: Int?
    private let state = StarMapDebugView.sampleState()
    private let map = GalaxyMap.standard

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Star Map").font(.title.bold()).foregroundStyle(Palette.text)
                Spacer()
                Text(selectedText).font(.title3).foregroundStyle(Palette.dimText)
            }
            StarMapView(map: map, state: state, hazards: true, highlight: [36, 37],
                        onSelectLane: { selected = $0 })
        }
        .padding(24)
    }

    private var selectedText: String {
        guard let id = selected else { return "Click a lane to select it" }
        let lane = map.lane(id)
        return "Selected: \(map.system(lane.a).name) to \(map.system(lane.b).name)"
    }

    /// Three Houses so closed twins show; Varn, Solace and the Pale Fleet each hold a few lanes.
    static func sampleState() -> GameState {
        var s = GameEngine(map: .standard).newGame(
            GameConfig(houses: [.varn, .solace, .paleFleet], frontierHazards: true, seed: 14))
        let claims: [Int: Int] = [
            10: 0, 3: 0, 38: 0, 21: 0,
            56: 1, 67: 1, 77: 1, 65: 1,
            47: 2, 41: 2, 24: 2, 59: 2, 63: 2,
        ]
        for (lane, seat) in claims {
            s.laneOwner[lane] = seat
            s.players[seat].lanes.append(lane)
        }
        return s
    }
}

#Preview("Star map") {
    StarMapDebugView()
        .frame(width: 1512, height: 900)
        .background(SpaceBackground())
}
#endif
