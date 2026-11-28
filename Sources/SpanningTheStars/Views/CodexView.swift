import SwiftUI

/// The Concord Codex: the bundled RULES.md, rendered block by block in a scrolling sheet.
struct CodexView: View {
    private enum Section: String, CaseIterable {
        case gameplay = "How to play"
        case reference = "Cards and symbols"
        case rules = "Rules"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .rules
    private let blocks = CodexBlock.parse(CodexText.load())

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("The Concord Codex", systemImage: "book.closed.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.brass)
                Spacer()
                GameButton("Done", help: "Close the Concord Codex") { dismiss() }
                    .buttonStyle(BrassButtonStyle())
                    .accessibilityLabel("Done")
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider().overlay(Palette.brass.opacity(0.3))
            Picker("Codex section", selection: $section) {
                ForEach(Section.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Switch between gameplay, the illustrated reference, and the rules")
            .onChange(of: section) { InteractionSound.selection.play() }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    switch section {
                    case .gameplay:
                        CodexBlockView(block: .heading(level: 1, text: section.rawValue))
                        ForEach(Array(HelpReference.gameplay.enumerated()), id: \.offset) { _, step in
                            CodexBlockView(block: .paragraph(step))
                        }
                    case .reference:
                        CodexReferenceView()
                    case .rules:
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            CodexBlockView(block: block)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .id(section)
        }
        .frame(width: 820, height: 700)
        .background(Palette.hex(0x0B1024))
        .environment(\.colorScheme, .dark)
    }
}

private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

private struct CodexBlockView: View {
    let block: CodexBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(.system(size: level == 1 ? 26 : level == 2 ? 19 : 16, weight: .semibold, design: .serif))
                .foregroundStyle(level == 1 ? Palette.brass : Palette.text)
                .padding(.top, level == 1 ? 0 : 12)
        case .paragraph(let text):
            Text(inline(text))
                .font(.system(size: 14))
                .foregroundStyle(Palette.text.opacity(0.92))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .quote(let text):
            Text(inline(text))
                .font(.system(size: 15, design: .serif).italic())
                .foregroundStyle(Palette.brass)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Palette.brass.opacity(0.6)).frame(width: 3) }
        case let .item(marker, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.brass)
                    .frame(minWidth: 16, alignment: .trailing)
                Text(inline(text))
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.text.opacity(0.92))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 6)
        case let .table(header, rows):
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: true) }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in tableCell(cell, header: false) }
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.brass.opacity(0.35), lineWidth: 1))
            .fixedSize()
        }
    }

    private func tableCell(_ text: String, header: Bool) -> some View {
        Text(inline(text))
            .font(.system(size: 13.5, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Palette.brass : Palette.text)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(header ? Palette.brass.opacity(0.1) : Color.clear)
    }
}

private struct CodexReferenceView: View {
    var body: some View {
        CodexBlockView(block: .heading(level: 2, text: "Cards and award"))
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                           GridItem(.flexible(), alignment: .topLeading)], spacing: 12) {
            ForEach(HelpReference.cards, id: \.art) { card in
                referenceRow(title: card.title, detail: card.detail) {
                    if let asset = ArtAsset(rawValue: card.art) {
                        ArtImage(asset)
                            .scaledToFit()
                            .frame(width: 52, height: 78)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        CodexBlockView(block: .heading(level: 2, text: "House status symbols"))
        ForEach(HelpHouseStat.allCases, id: \.self) { stat in
            referenceRow(title: stat.title, detail: stat.detail) {
                Image(systemName: stat.symbol)
                    .foregroundStyle(Palette.brass)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
        }
    }

    private func referenceRow<Illustration: View>(title: String, detail: String,
                                                    @ViewBuilder illustration: () -> Illustration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            illustration()
            VStack(alignment: .leading, spacing: 4) {
                Text(title).bold().foregroundStyle(Palette.text)
                Text(detail).foregroundStyle(Palette.dimText)
            }
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
