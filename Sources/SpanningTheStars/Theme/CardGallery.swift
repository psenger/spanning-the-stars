import SwiftUI
import StarsCore

#if DEBUG

/// Debug screen showing every card face, both backs and a contract. Launch with `-gallery`.
struct CardGalleryView: View {
    private var cards: [Card] { ResourceColor.allCases.map { .resource($0) } + [.core] }

    var body: some View {
        GeometryReader { geo in
            // Nine faces across the window width, at most 220 tall.
            let height = min(220, (geo.size.width - 48 - 8 * 12) / 9 / CardMetrics.aspect)
            let cardSize = CardMetrics.size(height: height)
            VStack(spacing: 20) {
                Text("Card Gallery").font(.title.bold()).foregroundStyle(Palette.text)
                HStack(spacing: 12) {
                    ForEach(cards, id: \.self) { ResourceCardView(card: $0, size: cardSize) }
                }
                HStack(spacing: 12) {
                    CardBackView(kind: .resource, size: cardSize)
                    CardBackView(kind: .contract, size: cardSize)
                    ForEach(Array(GalaxyMap.standard.contracts.prefix(2))) {
                        ContractCardView(contract: $0, completed: nil, size: cardSize)
                    }
                    if let c = GalaxyMap.standard.contracts.dropFirst(2).first {
                        ContractCardView(contract: c, completed: true, size: cardSize)
                    }
                }
            }
            .padding(24)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
#endif
