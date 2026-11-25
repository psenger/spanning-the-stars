import Foundation
import Testing

@Suite struct ArtTests {
    static let table: [(String, String)] = {
        let card = "0 0 200 300"
        var t: [(String, String)] = []
        for n in ["red", "purple", "black", "white", "blue", "green", "yellow", "orange", "core"] {
            t.append(("card-\(n)", card))
            t.append(("icon-\(n)", "0 0 64 64"))
        }
        for n in ["card-back-resource", "contract-back", "contract-front", "award-great-span"] {
            t.append((n, card))
        }
        for n in ["varn", "solace", "meridian", "ashkar", "palefleet"] {
            t.append(("house-\(n)", "0 0 128 128"))
        }
        for n in ["coreworlds", "shatteredrim", "veilnebula", "emberbelt"] {
            t.append(("star-\(n)", "0 0 48 48"))
        }
        t.append(("glyph-spectrum", "0 0 32 32"))
        t.append(("glyph-gravity", "0 0 32 32"))
        t.append(("bg-starfield", "0 0 1512 945"))
        t.append(("map-backdrop", "0 0 1000 620"))
        t.append(("title-emblem", "0 0 512 512"))
        return t
    }()

    static let artDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/SpanningTheStars/Resources/Art")

    @Test func allArtFilesExistWithContractViewBox() throws {
        #expect(Self.table.count == 36)
        for (name, viewBox) in Self.table {
            let url = Self.artDir.appendingPathComponent("\(name).svg")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("viewBox=\"\(viewBox)\""), "\(name) viewBox")
        }
    }

    @Test func artUsesOnlyAllowedFeatures() throws {
        let banned = ["<image", "<script", "<style", "<filter", "filter=", "<foreignObject", "href=\"http"]
        for (name, _) in Self.table {
            let text = try String(contentsOf: Self.artDir.appendingPathComponent("\(name).svg"), encoding: .utf8)
            for b in banned { #expect(!text.contains(b), "\(name) contains \(b)") }
        }
    }

    @Test func finalArtHasNoText() throws {
        for (name, _) in Self.table {
            let text = try String(contentsOf: Self.artDir.appendingPathComponent("\(name).svg"), encoding: .utf8)
            #expect(!text.contains("<text"), "\(name) still contains <text")
        }
    }
}
