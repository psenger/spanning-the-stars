import SwiftUI
import StarsCore

/// Colors for the whole app. Hex values are sRGB.
enum Palette {
    static func hex(_ v: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: opacity)
    }

    static let spaceTop = hex(0x070B1F)
    static let spaceBottom = hex(0x010206)
    static let background = LinearGradient(colors: [spaceTop, spaceBottom], startPoint: .top, endPoint: .bottom)
    static let brass = hex(0xC9A45C)
    static let text = hex(0xEEF1FA)
    static let dimText = hex(0x9AA3BD)

    static func resource(_ c: ResourceColor) -> Color {
        switch c {
        case .red: hex(0xE0443E)
        case .purple: hex(0x9B5DE5)
        case .black: hex(0x2B2B33)
        case .white: hex(0xF2F2F2)
        case .blue: hex(0x3FA7F5)
        case .green: hex(0x4CC36B)
        case .yellow: hex(0xF4D03F)
        case .orange: hex(0xF28C28)
        }
    }

    static func card(_ c: Card) -> Color {
        switch c {
        case .core: hex(0xD7B6FF)
        case .resource(let r): resource(r)
        }
    }

    static func house(_ h: House) -> Color {
        switch h {
        case .varn: hex(0xB3262B)
        case .solace: hex(0x2F5FC8)
        case .meridian: hex(0x2E8B57)
        case .ashkar: hex(0xD9A520)
        case .paleFleet: hex(0x14141A)
        }
    }

    /// Pale Fleet black needs a pale rim to stay visible on dark backgrounds.
    static func houseRim(_ h: House) -> Color {
        h == .paleFleet ? hex(0xDCE3F5) : house(h).opacity(0.9)
    }

    static func region(_ r: Region) -> Color {
        switch r {
        case .coreWorlds: hex(0xE0B050)
        case .shatteredRim: hex(0x7D93B0)
        case .veilNebula: hex(0x9A6FD8)
        case .emberBelt: hex(0xE0653A)
        }
    }
}

/// Dark backdrop used behind title, setup, hand-off and game content. Fills whatever space it is
/// given: the starfield is scaled to fill and clipped, never stretched.
struct SpaceBackground: View {
    var body: some View {
        Palette.background
            .overlay { ArtImage(.bgStarfield).scaledToFill() }
            .clipped()
    }
}
