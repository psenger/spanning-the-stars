import SwiftUI
import StarsCore

/// Opened by clicking a lane: shows why it cannot be anchored, or lists every way to pay for it.
struct ClaimSheet: View {
    let lane: Lane
    let state: GameState
    let engine: GameEngine
    let options: TurnOptions
    let perform: (Action) -> Void
    /// The engine's last refusal, shown if confirming fails.
    let error: RuleError?
    let close: () -> Void

    @State private var selected = 0

    enum Availability: Equatable {
        case payable([Payment])
        case blocked(String)
    }

    var body: some View {
        let map = engine.map
        let hazards = state.config.frontierHazards
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                PanelTitle(text: "Anchor a lane")
                Text("\(map.system(lane.a).name) to \(map.system(lane.b).name)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    LaneSwatch(color: lane.color)
                    Text(summary(hazards: hazards))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.dimText)
                }
                if let note = hazardNote(hazards: hazards) {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.brass.opacity(0.9))
                }
            }

            switch ClaimSheet.availability(lane, state: state, engine: engine, options: options) {
            case .blocked(let message):
                blocked(message)
            case .payable(let payments):
                choose(payments)
            }
        }
    }

    private func summary(hazards: Bool) -> String {
        let beacons = beaconCost(lane, hazards: hazards)
        return "Length \(lane.length), +\(lanePoints(lane.length)) Concord Standing, "
            + "\(beacons) Anchor Beacon\(beacons == 1 ? "" : "s"). Cost: \(StarMapView.costText(lane, hazards: hazards))"
    }

    private func hazardNote(hazards: Bool) -> String? {
        guard hazards else { return nil }
        switch lane.hazard {
        case .spectrum: return "Spectrum Lane: every card must be a different resource; Quantum Cores fill any gap."
        case .gravityWell: return "Gravity Well: one card fewer, but one extra Anchor Beacon is lost."
        case .none: return nil
        }
    }

    private func blocked(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(message, systemImage: "nosign")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.text)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.hex(0x2A0E12, opacity: 0.7), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hex(0xE0443E, opacity: 0.5), lineWidth: 1))
            HStack {
                Spacer()
                Button("Close", action: close)
                    .buttonStyle(BrassButtonStyle(prominent: false))
                    .accessibilityLabel("Close")
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func choose(_ payments: [Payment]) -> some View {
        let pick = min(selected, payments.count - 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(payments.count == 1 ? "Payment" : "Choose a payment (\(payments.count) ways)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(Array(payments.enumerated()), id: \.offset) { i, payment in
                        PaymentRow(payment: payment, selected: i == pick) { selected = i }
                    }
                }
                .padding(.trailing, payments.count > 6 ? 10 : 0)
            }
            .frame(maxHeight: 290)
            .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error.themedMessage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.hex(0xFF8A80))
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: close)
                    .buttonStyle(BrassButtonStyle(prominent: false))
                    .accessibilityLabel("Cancel")
                    .keyboardShortcut(.cancelAction)
                Button("Anchor lane (+\(lanePoints(lane.length)))") {
                    perform(.claim(laneID: lane.id, payment: payments[pick]))
                }
                .buttonStyle(BrassButtonStyle())
                .accessibilityLabel("Anchor lane, plus \(lanePoints(lane.length)) Standing")
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The engine's checks, in its order: the turn phase, then `claimBlocker`, then the hand.
    static func availability(_ lane: Lane, state: GameState, engine: GameEngine,
                             options: TurnOptions) -> Availability {
        switch state.phase {
        case .awaitingAction: break
        case .drawingSecondCard:
            return .blocked("Take your second Resource Card first. Anchoring a lane takes a whole turn.")
        default:
            return .blocked("No lane can be anchored right now.")
        }
        let seat = state.current
        let player = state.players[seat]
        let hazards = state.config.frontierHazards
        if let blocker = engine.claimBlocker(lane, seat: seat, in: state) {
            switch blocker {
            case .laneTaken:
                let owner = state.laneOwner[lane.id]
                if owner == seat { return .blocked("Your House already anchors this lane.") }
                let name = owner.map { state.players[$0].house.displayName } ?? "another House"
                return .blocked("Already anchored by \(name).")
            case .laneClosed:
                return .blocked("Lane closed. Its twin is anchored, and with 3 or fewer Houses "
                                + "only one lane of a High-Traffic Corridor may be used.")
            case .ownsTwin:
                return .blocked("Your House already anchors the twin of this High-Traffic Corridor.")
            case .notEnoughBeacons:
                let cost = beaconCost(lane, hazards: hazards)
                return .blocked("Not enough beacons. This lane needs \(cost) Anchor Beacons "
                                + "and your House has \(player.beacons).")
            default:
                return .blocked(blocker.themedMessage)
            }
        }
        let payments = options.payments[lane.id] ?? []
        if payments.isEmpty {
            return .blocked("Your hand cannot pay for this lane. It costs \(StarMapView.costText(lane, hazards: hazards)).")
        }
        return .payable(payments)
    }
}

private struct LaneSwatch: View {
    let color: LaneColor

    var body: some View {
        let fill: Color = switch color {
        case .color(let r): Palette.resource(r)
        case .open: Palette.hex(0x8E95A6)
        }
        RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            .frame(width: 18, height: 8)
    }
}

private struct PaymentRow: View {
    let payment: Payment
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Palette.brass : Palette.dimText)
                ForEach(PaymentRow.parts(payment), id: \.card) { part in
                    HStack(spacing: 5) {
                        ArtImage(.icon(part.card)).frame(width: 20, height: 20)
                        Text("\(part.count) \(part.card.displayName)")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.text)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(PaymentRow.tint(part.card).opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(PaymentRow.tint(part.card).opacity(0.55), lineWidth: 1))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? Palette.brass.opacity(0.12) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Palette.brass.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(PaymentRow.parts(payment).map { "\($0.count) \($0.card.displayName)" }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Dark-Matter Ballast black would vanish on the dark sheet, so it is lifted toward gray.
    static func tint(_ card: Card) -> Color {
        card == .resource(.black) ? Palette.dimText : Palette.card(card)
    }

    /// Payment cards in hand order: colors first, then Quantum Cores.
    static func parts(_ p: Payment) -> [(card: Card, count: Int)] {
        Card.handOrder.compactMap { card in p.counts[card].map { (card, $0) } }
    }
}
