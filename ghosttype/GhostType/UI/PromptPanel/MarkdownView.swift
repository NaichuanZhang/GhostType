import SwiftUI
import Highlightr

/// Renders markdown text with styled code blocks, headings, lists, and inline formatting.
/// Designed for streaming — handles partial/incomplete markdown gracefully.
struct MarkdownView: View {
    let text: String

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block Types

    private enum Block {
        case codeBlock(language: String, code: String)
        case heading(level: Int, text: String)
        case listItem(bullet: String, text: String)
        case paragraph(text: String)
        case divider
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .listItem(let bullet, let text):
            listItemView(bullet: bullet, text: text)
        case .paragraph(let text):
            paragraphView(text: text)
        case .divider:
            Divider().padding(.vertical, 2)
        }
    }

    // MARK: - Syntax Highlighting

    private static let highlightr: Highlightr? = Highlightr()

    private func highlightCode(_ code: String, language: String) -> AttributedString {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? "atom-one-dark" : "atom-one-light"

        if let h = Self.highlightr {
            h.setTheme(to: theme)
            h.theme.setCodeFont(.monospacedSystemFont(ofSize: 12, weight: .regular))
            let lang = language.isEmpty ? nil : language
            if let highlighted = h.highlight(code, as: lang) {
                // Strip background color so our code block background shows through
                let mutable = NSMutableAttributedString(attributedString: highlighted)
                mutable.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: mutable.length))
                return AttributedString(mutable)
            }
        }

        // Fallback: plain monospace
        var plain = AttributedString(code)
        plain.font = .system(size: 12, design: .monospaced)
        return plain
    }

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightCode(code, language: language))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, language.isEmpty ? 8 : 4)
                    .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func headingView(level: Int, text: String) -> some View {
        let fontSize: CGFloat = level == 1 ? 17 : level == 2 ? 15 : 14
        let weight: Font.Weight = level <= 2 ? .semibold : .medium
        return inlineMarkdown(text)
            .font(.system(size: fontSize, weight: weight))
            .textSelection(.enabled)
    }

    private func listItemView(bullet: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(bullet)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(minWidth: 12, alignment: .trailing)
            inlineMarkdown(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
    }

    private func paragraphView(text: String) -> some View {
        inlineMarkdown(text)
            .font(.system(size: 13))
            .textSelection(.enabled)
    }

    /// Renders inline markdown (bold, italic, code, links) using AttributedString.
    /// Falls back to plain Text if parsing fails (e.g. during streaming with incomplete markup).
    private func inlineMarkdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    // MARK: - Parser

    private func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // skip closing ```
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Headings
            if line.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
                i += 1; continue
            }
            if line.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
                i += 1; continue
            }
            if line.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
                i += 1; continue
            }

            // Unordered list items (- or *)
            if (line.hasPrefix("- ") || line.hasPrefix("* ")) && !isHorizontalRule(line) {
                blocks.append(.listItem(bullet: "\u{2022}", text: String(line.dropFirst(2))))
                i += 1; continue
            }

            // Ordered list items (1. 2. etc.)
            if let range = line.range(of: #"^(\d+)\.\s"#, options: .regularExpression) {
                let number = line[line.startIndex..<line.index(before: range.upperBound)]
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ".", with: "")
                let content = String(line[range.upperBound...])
                blocks.append(.listItem(bullet: "\(number).", text: content))
                i += 1; continue
            }

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1; continue
            }

            // Paragraph — collect consecutive non-special lines
            var paraLines: [String] = [line]
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty
                    || next.hasPrefix("```")
                    || next.hasPrefix("# ") || next.hasPrefix("## ") || next.hasPrefix("### ")
                    || next.hasPrefix("- ") || next.hasPrefix("* ")
                    || next.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
                    || nextTrimmed == "---" || nextTrimmed == "***" || nextTrimmed == "___" {
                    break
                }
                paraLines.append(next)
                i += 1
            }
            blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
        }

        return blocks
    }

    private func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || t == "***" || t == "___"
    }
}
