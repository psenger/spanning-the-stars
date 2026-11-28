import AppKit
import Foundation

/// Generates the localized Apple Help book from the same reference and rules the Codex uses.
@main
struct BuildHelp {
    private static let title = "Spanning the Stars Help"
    private static let identifier = "local.spanningthestars.help"

    @MainActor
    static func main() throws {
        let source = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let book = URL(filePath: CommandLine.arguments[2], directoryHint: .isDirectory)
        let contents = book.appending(path: "Contents")
        let resources = contents.appending(path: "Resources")
        let english = resources.appending(path: "en.lproj")
        let artwork = resources.appending(path: "Artwork")
        let files = FileManager.default

        try files.createDirectory(at: english, withIntermediateDirectories: true)
        try files.createDirectory(at: artwork, withIntermediateDirectories: true)

        let plist = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": title,
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1",
            "CFBundleVersion": "2",
            "HPDBookAccessPath": "index.html",
            "HPDBookIndexPath": "SpanningTheStars.helpindex",
            "HPDBookTitle": title,
            "HPDBookType": "3"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        try "\"HPDBookTitle\" = \"\(title)\";\n".write(to: english.appending(path: "InfoPlist.strings"),
                                                            atomically: true, encoding: .utf8)

        for card in HelpReference.cards {
            let name = card.art + ".svg"
            let destination = artwork.appending(path: name)
            if files.fileExists(atPath: destination.path) { try files.removeItem(at: destination) }
            try files.copyItem(at: source.appending(path: "Art/\(name)"), to: destination)
        }
        for stat in HelpHouseStat.allCases {
            try saveSymbol(stat, at: artwork)
        }

        let reference = HelpReference.cards.map { referenceRow(name: $0.title, detail: $0.detail, image: $0.art + ".svg") }
        let stats = HelpHouseStat.allCases.map { referenceRow(name: $0.title, detail: $0.detail, image: $0.symbol + ".png") }
        let rules = try String(contentsOf: source.appending(path: "RULES.md"), encoding: .utf8)

        try page("How to play", body: gameplayBody(), isIndex: true)
            .write(to: english.appending(path: "index.html"), atomically: true, encoding: .utf8)
        try page("Cards and House symbols", body: """
            <h1>Cards and award</h1><div class="cards">\(reference.joined(separator: "\n"))</div>
            <h2>House status symbols</h2><div class="stats">\(stats.joined(separator: "\n"))</div>
            """).write(to: english.appending(path: "reference.html"), atomically: true, encoding: .utf8)
        try page("Rules", body: renderRules(CodexBlock.parse(rules)))
            .write(to: english.appending(path: "rules.html"), atomically: true, encoding: .utf8)
    }

    private static func gameplayBody() -> String {
        typealias Example = HelpReference.FirstLane
        var links: [String] = []
        var sections: [String] = []
        for section in HelpReference.gameplay {
            links.append("<li><a href=\"#\(section.id)\">\(escape(section.title))</a></li>")
            let steps = section.steps.map { "<p>\(inline($0))</p>" }.joined(separator: "\n")
            sections.append("""
                <section id="\(section.id)"><h2>\(escape(section.title))</h2>
                \(steps)
                </section>
                """)
            if section.id == "turn" {
                links.append("<li><a href=\"#\(Example.anchor)\">Lane example</a></li>")
                sections.append(laneExample())
            }
        }
        return """
            <h1>How to play</h1>
            <p>\(escape(HelpReference.gameplayIntro))</p>
            <ul class="guide-links">\(links.joined(separator: "\n"))</ul>
            \(sections.joined(separator: "\n"))
            """
    }

    private static func laneExample() -> String {
        typealias Example = HelpReference.FirstLane
        let cards = String(repeating: "<img src=\"../Artwork/\(Example.cardArt).svg\" alt=\"\">", count: Example.cost)
        let slots = String(repeating: "<span class=\"lane-slot\"></span>", count: Example.cost)
        let steps = Example.steps.map { "<li>\(inline($0))</li>" }.joined(separator: "\n")
        return """
            <section class="lane-example" id="\(Example.anchor)">
              <h2>\(escape(Example.title))</h2>
              <figure class="lane-figure" aria-label="\(escape(Example.illustrationDescription))">
                <div class="lane-payment" aria-hidden="true">\(cards)<span>\(Example.cost) × \(escape(Example.cardName))</span></div>
                <div class="lane-path" aria-hidden="true"><span>→</span>\(escape(Example.from)) \(slots) \(escape(Example.to))</div>
              </figure>
              <ol class="steps">\(steps)</ol>
            </section>
            """
    }

    @MainActor
    private static func saveSymbol(_ stat: HelpHouseStat, at artwork: URL) throws {
        guard let symbol = NSImage(systemSymbolName: stat.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 28, weight: .regular)),
              let tiff = symbol.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Cannot render \(stat.symbol)"])
        }
        try png.write(to: artwork.appending(path: stat.symbol + ".png"))
    }

    private static func referenceRow(name: String, detail: String, image: String) -> String {
        """
        <div class="reference">
          <img src="../Artwork/\(escape(image))" alt="">
          <div><h3>\(escape(name))</h3><p>\(escape(detail))</p></div>
        </div>
        """
    }

    private static func page(_ heading: String, body: String, isIndex: Bool = false) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          \(isIndex ? "<meta name=\"AppleTitle\" content=\"\(identifier)\">" : "")
          <title>\(escape(heading)) | \(title)</title>
          <style>
            :root { color-scheme: light dark; }
            body { font: 15px/1.5 -apple-system, sans-serif; margin: 24px auto; max-width: 760px; padding: 0 20px; }
            nav { display: flex; flex-wrap: wrap; gap: 12px; border-bottom: 1px solid GrayText; padding-bottom: 12px; }
            h1, h2, h3 { line-height: 1.2; }
            h2 { margin-top: 1.6em; }
            .steps li { margin-bottom: .65em; }
            .guide-links { display: flex; flex-wrap: wrap; gap: 4px 16px; list-style: none; padding: 0; }
            .lane-example { margin: 24px 0; padding: 14px 18px; border: 1px solid GrayText; border-radius: 10px; }
            .lane-example h2 { margin-top: 0; }
            .lane-figure { margin: 12px 0; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
            .lane-payment, .lane-path { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
            .lane-payment img { width: 39px; height: 59px; object-fit: contain; }
            .lane-slot { display: inline-block; background: #e0443e; border-radius: 4px; width: 22px; height: 11px; }
            .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 16px; }
            .reference { display: flex; align-items: flex-start; gap: 12px; break-inside: avoid; }
            .reference h3 { font-size: 1em; margin: 0 0 4px; }
            .reference p { margin: 0; }
            .cards img { flex: none; width: 56px; height: 84px; object-fit: contain; }
            .stats .reference { margin-bottom: 14px; }
            .stats img { flex: none; width: 26px; height: 26px; object-fit: contain; }
            @media (prefers-color-scheme: dark) { .stats img { filter: invert(1); } }
            table { border-collapse: collapse; }
            th, td { border: 1px solid GrayText; padding: .3em .65em; text-align: left; }
          </style>
        </head>
        <body>
          <nav aria-label="Help topics">
            <a href="index.html">How to play</a>
            <a href="reference.html">Cards and House symbols</a>
            <a href="rules.html">Rules</a>
          </nav>
          <main>\(body)</main>
        </body>
        </html>
        """
    }

    private static func renderRules(_ blocks: [CodexBlock]) -> String {
        var html = ""
        var list: String?
        for block in blocks {
            if case let .item(marker, text) = block {
                let kind = marker == "•" ? "ul" : "ol"
                if list != kind {
                    if let list { html += "</\(list)>\n" }
                    html += "<\(kind)>\n"
                    list = kind
                }
                html += "<li>\(inline(text))</li>\n"
                continue
            }
            if let open = list {
                html += "</\(open)>\n"
                list = nil
            }
            switch block {
            case let .heading(level, text):
                html += "<h\(level)>\(inline(text))</h\(level)>\n"
            case .paragraph(let text):
                html += "<p>\(inline(text))</p>\n"
            case .quote(let text):
                html += "<blockquote>\(inline(text))</blockquote>\n"
            case let .table(header, rows):
                html += "<table><thead>\(tableRow(header, tag: "th"))</thead><tbody>"
                html += rows.map { tableRow($0, tag: "td") }.joined(separator: "\n")
                html += "</tbody></table>\n"
            case .item:
                break
            }
        }
        if let list { html += "</\(list)>\n" }
        return html
    }

    private static func tableRow(_ cells: [String], tag: String) -> String {
        "<tr>" + cells.map { "<\(tag)>\(inline($0))</\(tag)>" }.joined() + "</tr>"
    }

    private static func inline(_ text: String) -> String {
        escape(text)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
            .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "<em>$1</em>", options: .regularExpression)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
