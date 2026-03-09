import SwiftUI
import Highlightr

/// Caches parsed markdown blocks incrementally — only re-parses from the point where new text was appended.
/// Invalidates when the text prefix no longer matches (e.g., new message).
final class MarkdownBlockCache {
    private var cachedBlocks: [MarkdownView.Block] = []
    private var lastParsedText: String = ""

    /// Returns parsed blocks for the given text, reusing cached results when possible.
    func blocks(for text: String) -> [MarkdownView.Block] {
        // Fast path: identical text — return cached
        if text == lastParsedText {
            return cachedBlocks
        }

        // Incremental path: text starts with the same prefix
        if !lastParsedText.isEmpty && text.hasPrefix(lastParsedText) {
            let newSuffix = String(text[lastParsedText.endIndex...])
            // Only do incremental if the last cached block might merge with new content.
            // For safety, re-parse the last block's worth of text plus the new suffix.
            // Find where the last block started by re-parsing from a safe point.
            let incrementalBlocks = parseIncrementally(fullText: text, previousText: lastParsedText, suffix: newSuffix)
            if let incrementalBlocks {
                cachedBlocks = incrementalBlocks
                lastParsedText = text
                return cachedBlocks
            }
        }

        // Full re-parse (prefix changed or first parse)
        cachedBlocks = MarkdownView.parseBlocksStatic(text)
        lastParsedText = text
        return cachedBlocks
    }

    /// Invalidates the cache, forcing a full re-parse on next call.
    func invalidate() {
        cachedBlocks = []
        lastParsedText = ""
    }

    /// Incremental re-parse: find the last block boundary (blank line) in the previous text,
    /// keep blocks that ended before it, and re-parse from the boundary through the end of new text.
    private func parseIncrementally(fullText: String, previousText: String, suffix: String) -> [MarkdownView.Block]? {
        guard cachedBlocks.count > 1 else { return nil }

        // Find the last block boundary (blank line) in the previously parsed text
        guard let boundaryRange = previousText.range(of: "\n\n", options: .backwards) else {
            return nil  // no boundary found — full re-parse
        }

        // Keep blocks parsed from the prefix before the boundary
        let prefixText = String(previousText[..<boundaryRange.lowerBound])
        let kept = MarkdownView.parseBlocksStatic(prefixText)

        // Re-parse from the boundary through the end of new text
        let tailStart = fullText.index(fullText.startIndex, offsetBy: prefixText.count)
        let tailText = String(fullText[tailStart...])
        let tailBlocks = MarkdownView.parseBlocksStatic(tailText)

        return kept + tailBlocks
    }
}

/// Renders markdown text with styled code blocks, headings, lists, and inline formatting.
/// Designed for streaming — handles partial/incomplete markdown gracefully.
struct MarkdownView: View {
    let text: String
    let isStreaming: Bool

    /// Shared cache for incremental block parsing during streaming.
    /// Using @State so it persists across view re-evaluations for the same MarkdownView identity.
    @State private var blockCache = MarkdownBlockCache()

    init(text: String, isStreaming: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
    }

    var body: some View {
        let blocks = blockCache.blocks(for: text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Block Types

    enum Block {
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
        // During streaming, skip expensive syntax highlighting — use plain monospace
        if isStreaming {
            var plain = AttributedString(code)
            plain.font = .system(size: 12, design: .monospaced)
            plain.foregroundColor = .primary
            return plain
        }

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

    // MARK: - Parser (static for cache use)

    static func parseBlocksStatic(_ text: String) -> [Block] {
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

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || t == "***" || t == "___"
    }
}
