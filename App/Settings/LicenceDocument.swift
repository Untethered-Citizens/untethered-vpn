import Foundation

/// `THIRD_PARTY_LICENSES.md`, split into blocks the About screen can show:
/// headings, paragraphs (inline Markdown), bullet lists and verbatim licence
/// texts. Only the Markdown that file uses is understood.
struct LicenceDocument: Equatable {

    enum Block: Equatable {
        case title(String)
        case heading(String)
        case paragraph(String)
        case bullets([String])
        case verbatim(String)
    }

    let blocks: [Block]

    init(markdown: String) {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var verbatim: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)) }
            paragraph = []
            bullets = []
        }

        for line in markdown.components(separatedBy: "\n") {
            if var lines = verbatim {
                if line.hasPrefix("```") {
                    blocks.append(.verbatim(lines.joined(separator: "\n").trimmingCharacters(in: .newlines)))
                    verbatim = nil
                } else {
                    lines.append(line)
                    verbatim = lines
                }
            } else if line.hasPrefix("```") {
                flush()
                verbatim = []
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flush()
                blocks.append(.title(String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") {
                if !paragraph.isEmpty { flush() }
                bullets.append(String(line.dropFirst(2)))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                if !bullets.isEmpty { flush() }
                paragraph.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        self.blocks = blocks
    }

    /// The copy bundled with the app, or nil if it's missing.
    static func bundled(in bundle: Bundle = .main) -> LicenceDocument? {
        guard let url = bundle.url(forResource: "THIRD_PARTY_LICENSES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return LicenceDocument(markdown: text)
    }
}
