import SwiftUI
import AppKit
import StarsCore

/// Every SVG in Resources/Art. The raw value is the file name without `.svg`.
enum ArtAsset: String, CaseIterable {
    case cardRed = "card-red", cardPurple = "card-purple", cardBlack = "card-black"
    case cardWhite = "card-white", cardBlue = "card-blue", cardGreen = "card-green"
    case cardYellow = "card-yellow", cardOrange = "card-orange", cardCore = "card-core"
    case cardBackResource = "card-back-resource", contractBack = "contract-back"
    case contractFront = "contract-front", awardGreatSpan = "award-great-span"
    case iconRed = "icon-red", iconPurple = "icon-purple", iconBlack = "icon-black"
    case iconWhite = "icon-white", iconBlue = "icon-blue", iconGreen = "icon-green"
    case iconYellow = "icon-yellow", iconOrange = "icon-orange", iconCore = "icon-core"
    case houseVarn = "house-varn", houseSolace = "house-solace", houseMeridian = "house-meridian"
    case houseAshkar = "house-ashkar", housePaleFleet = "house-palefleet"
    case starCoreWorlds = "star-coreworlds", starShatteredRim = "star-shatteredrim"
    case starVeilNebula = "star-veilnebula", starEmberBelt = "star-emberbelt"
    case glyphSpectrum = "glyph-spectrum", glyphGravity = "glyph-gravity"
    case bgStarfield = "bg-starfield", mapBackdrop = "map-backdrop", titleEmblem = "title-emblem"

    static func card(_ c: Card) -> ArtAsset {
        switch c {
        case .core: .cardCore
        case .resource(let r):
            switch r {
            case .red: .cardRed
            case .purple: .cardPurple
            case .black: .cardBlack
            case .white: .cardWhite
            case .blue: .cardBlue
            case .green: .cardGreen
            case .yellow: .cardYellow
            case .orange: .cardOrange
            }
        }
    }

    static func icon(_ c: Card) -> ArtAsset {
        switch c {
        case .core: .iconCore
        case .resource(let r):
            switch r {
            case .red: .iconRed
            case .purple: .iconPurple
            case .black: .iconBlack
            case .white: .iconWhite
            case .blue: .iconBlue
            case .green: .iconGreen
            case .yellow: .iconYellow
            case .orange: .iconOrange
            }
        }
    }

    static func house(_ h: House) -> ArtAsset {
        switch h {
        case .varn: .houseVarn
        case .solace: .houseSolace
        case .meridian: .houseMeridian
        case .ashkar: .houseAshkar
        case .paleFleet: .housePaleFleet
        }
    }

    static func star(_ r: Region) -> ArtAsset {
        switch r {
        case .coreWorlds: .starCoreWorlds
        case .shatteredRim: .starShatteredRim
        case .veilNebula: .starVeilNebula
        case .emberBelt: .starEmberBelt
        }
    }
}

/// Loads an `ArtAsset` SVG as a resizable vector image. A missing file shows a magenta rectangle.
struct ArtImage: View {
    let asset: ArtAsset
    init(_ asset: ArtAsset) { self.asset = asset }

    @MainActor private static var cache: [ArtAsset: NSImage] = [:]

    private static let artFolder: URL? = ResourceLocator.url("Art")

    @MainActor private static func image(for asset: ArtAsset) -> NSImage? {
        if let hit = cache[asset] { return hit }
        guard let url = artFolder?.appendingPathComponent("\(asset.rawValue).svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[asset] = img
        return img
    }

    var body: some View {
        if let img = Self.image(for: asset) {
            Image(nsImage: img).resizable()
        } else {
            Rectangle().fill(Color(red: 1, green: 0, blue: 1))
        }
    }
}
