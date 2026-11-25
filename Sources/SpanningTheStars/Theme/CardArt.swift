import SwiftUI
import StarsCore

/// Card faces share the 200x300 art ratio.
enum CardMetrics {
    static let aspect: CGFloat = 200.0 / 300.0
    static func size(height: CGFloat) -> CGSize { CGSize(width: height * aspect, height: height) }
}

struct ResourceCardView: View {
    let card: Card
    let size: CGSize

    private var name: String {
        switch card {
        case .core: "Quantum Core"
        case .resource(let r): r.resourceName
        }
    }

    var body: some View {
        let u = size.width / 200
        ZStack {
            ArtImage(.card(card))
            // Final art keeps y 236...290 dark and calm for the name.
            Text(name)
                .font(.system(size: 17 * u, weight: .semibold))
                .foregroundStyle(Color(white: 0.97))
                .shadow(color: .black.opacity(0.8), radius: 2 * u, y: u)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 176 * u, height: 54 * u)
                .position(x: 100 * u, y: 263 * u)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

struct ContractCardView: View {
    let contract: Contract
    /// nil: not yet resolved; true: completed; false: failed.
    var completed: Bool?
    let size: CGSize
    var map: GalaxyMap = .standard

    var body: some View {
        let u = size.width / 200
        let a = map.system(contract.a).name
        let b = map.system(contract.b).name
        ZStack {
            ArtImage(.contractFront)
            VStack(spacing: 2 * u) {
                Text(a)
                Text("to").font(.system(size: 11 * u, weight: .regular)).foregroundStyle(Palette.brass)
                Text(b)
            }
            .font(.system(size: 17 * u, weight: .semibold))
            .foregroundStyle(Palette.text)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .multilineTextAlignment(.center)
            .frame(width: 112 * u, height: 92 * u)
            .position(x: 84 * u, y: 64 * u)

            Text(contract.flavor)
                .font(.system(size: 12 * u, weight: .regular).italic())
                .foregroundStyle(Palette.text.opacity(0.9))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .frame(width: 156 * u, height: 130 * u)
                .position(x: 100 * u, y: 185 * u)

            Text("\(contract.value)")
                .font(.system(size: 22 * u, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.brass)
                .frame(width: 48 * u, height: 48 * u)
                .position(x: 166 * u, y: 36 * u)

            if let completed {
                Text(completed ? "Fulfilled" : "Unfulfilled")
                    .font(.system(size: 13 * u, weight: .bold))
                    .foregroundStyle(completed ? Color.green : Color.red)
                    .padding(.horizontal, 8 * u).padding(.vertical, 3 * u)
                    .background(.black.opacity(0.7), in: Capsule())
                    .position(x: 100 * u, y: 262 * u)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct CardBackView: View {
    enum Kind { case resource, contract }
    let kind: Kind
    let size: CGSize

    var body: some View {
        ArtImage(kind == .resource ? .cardBackResource : .contractBack)
            .frame(width: size.width, height: size.height)
            .accessibilityLabel(kind == .resource ? "Resource Card deck" : "Concord Contract deck")
    }
}
