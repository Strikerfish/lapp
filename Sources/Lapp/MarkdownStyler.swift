import AppKit

/// Styles markdown in place as you type. The text never changes -- only its attributes --
/// so what you see is always exactly what gets written to disk.
///
/// Only the paragraphs touched by an edit are restyled, never the whole document.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    var theme: Theme = .current
    var baseSize: CGFloat = 13

    private var isStyling = false

    // Compiled once. All of these are anchored or bounded so they can't backtrack badly
    // on a long line.
    private static let heading  = try! NSRegularExpression(pattern: "^(#{1,6})[ \t]+(.*)$")
    private static let bullet   = try! NSRegularExpression(pattern: "^([ \t]*)([-*+])[ \t]+")
    private static let ordered  = try! NSRegularExpression(pattern: "^([ \t]*)([0-9]+\\.)[ \t]+")
    private static let quote    = try! NSRegularExpression(pattern: "^[ \t]*(>[ \t]?)")
    private static let bold     = try! NSRegularExpression(pattern: "\\*\\*([^*\n]+)\\*\\*")
    private static let emphasis = try! NSRegularExpression(pattern: "(?<![*\\w])[*_]([^*_\n]+)[*_](?![*\\w])")
    private static let code     = try! NSRegularExpression(pattern: "`([^`\n]+)`")
    private static let checked  = try! NSRegularExpression(pattern: "^[ \t]*[-*+][ \t]+\\[[xX]\\]")

    // MARK: - Fonts

    var baseFont: NSFont { NSFont.systemFont(ofSize: baseSize, weight: .regular) }

    private func headingFont(level: Int) -> NSFont {
        let bump: CGFloat = [7, 4, 2, 1, 1, 1][min(level, 6) - 1]
        return NSFont.systemFont(ofSize: baseSize + bump, weight: level <= 2 ? .semibold : .medium)
    }

    private var boldFont: NSFont { NSFont.systemFont(ofSize: baseSize, weight: .semibold) }
    private var italicFont: NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
    }
    private var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: baseSize - 0.5, weight: .regular)
    }

    var baseParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.28
        style.paragraphSpacing = baseSize * 0.35
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: theme.text, .paragraphStyle: baseParagraphStyle]
    }

    // MARK: - Delegate

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isStyling else { return }
        let text = textStorage.string as NSString
        let safe = NSRange(location: min(editedRange.location, text.length),
                           length: min(editedRange.length, max(0, text.length - min(editedRange.location, text.length))))
        style(textStorage, range: text.paragraphRange(for: safe))
    }

    func styleAll(_ textStorage: NSTextStorage) {
        style(textStorage, range: NSRange(location: 0, length: textStorage.length))
    }

    // MARK: - Styling

    private func style(_ textStorage: NSTextStorage, range: NSRange) {
        guard range.length >= 0, range.location >= 0,
              range.location + range.length <= textStorage.length else { return }

        isStyling = true
        defer { isStyling = false }

        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes, range: range)

        let text = textStorage.string as NSString
        text.enumerateSubstrings(in: range, options: [.byParagraphs, .substringNotRequired]) { _, lineRange, _, _ in
            self.styleLine(textStorage, text: text, line: lineRange)
        }
        // A trailing empty paragraph produces no substring above; nothing to style there.
        textStorage.endEditing()
    }

    private func styleLine(_ storage: NSTextStorage, text: NSString, line: NSRange) {
        let content = text.substring(with: line)
        let local = NSRange(location: 0, length: (content as NSString).length)

        // Block level: heading, list, quote.
        if let match = Self.heading.firstMatch(in: content, range: local) {
            let level = match.range(at: 1).length
            storage.addAttribute(.font, value: headingFont(level: level), range: line)
            storage.addAttribute(.foregroundColor, value: theme.muted, range: shift(match.range(at: 1), by: line.location))
            let style = NSMutableParagraphStyle()
            style.setParagraphStyle(baseParagraphStyle)
            style.paragraphSpacingBefore = baseSize * (level == 1 ? 0.9 : 0.6)
            style.paragraphSpacing = baseSize * 0.2
            storage.addAttribute(.paragraphStyle, value: style, range: line)
        } else if let match = Self.bullet.firstMatch(in: content, range: local)
                    ?? Self.ordered.firstMatch(in: content, range: local) {
            let marker = shift(match.range(at: 2), by: line.location)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: marker)
            // Hanging indent so wrapped lines line up under the text, not under the marker.
            let style = NSMutableParagraphStyle()
            style.setParagraphStyle(baseParagraphStyle)
            let indent = CGFloat(match.range.length) * baseSize * 0.5
            style.headIndent = indent
            style.paragraphSpacing = baseSize * 0.15
            storage.addAttribute(.paragraphStyle, value: style, range: line)

            if Self.checked.firstMatch(in: content, range: local) != nil {
                storage.addAttribute(.foregroundColor, value: theme.muted, range: line)
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: line)
            }
        } else if let match = Self.quote.firstMatch(in: content, range: local) {
            storage.addAttribute(.foregroundColor, value: theme.muted, range: line)
            storage.addAttribute(.font, value: italicFont, range: line)
            storage.addAttribute(.foregroundColor, value: theme.accent, range: shift(match.range(at: 1), by: line.location))
        }

        // Inline level.
        for match in Self.bold.matches(in: content, range: local) {
            storage.addAttribute(.font, value: boldFont, range: shift(match.range(at: 1), by: line.location))
            mute(storage, markersAround: match, inner: 1, line: line)
        }
        for match in Self.emphasis.matches(in: content, range: local) {
            let inner = shift(match.range(at: 1), by: line.location)
            let existing = storage.attribute(.font, at: inner.location, effectiveRange: nil) as? NSFont
            if existing?.fontDescriptor.symbolicTraits.contains(.bold) != true {
                storage.addAttribute(.font, value: italicFont, range: inner)
            }
            mute(storage, markersAround: match, inner: 1, line: line)
        }
        for match in Self.code.matches(in: content, range: local) {
            let whole = shift(match.range, by: line.location)
            storage.addAttribute(.font, value: codeFont, range: whole)
            storage.addAttribute(.backgroundColor, value: theme.codeBackground, range: whole)
            storage.addAttribute(.foregroundColor, value: theme.muted, range: whole)
            storage.addAttribute(.foregroundColor, value: theme.text, range: shift(match.range(at: 1), by: line.location))
        }
    }

    /// Dims the `**` / `*` characters on either side of an inline span.
    private func mute(_ storage: NSTextStorage, markersAround match: NSTextCheckingResult, inner group: Int, line: NSRange) {
        let whole = match.range
        let content = match.range(at: group)
        let leading = NSRange(location: whole.location, length: content.location - whole.location)
        let trailingStart = content.location + content.length
        let trailing = NSRange(location: trailingStart, length: whole.location + whole.length - trailingStart)
        for range in [leading, trailing] where range.length > 0 {
            storage.addAttribute(.foregroundColor, value: theme.muted, range: shift(range, by: line.location))
        }
    }

    private func shift(_ range: NSRange, by offset: Int) -> NSRange {
        NSRange(location: range.location + offset, length: range.length)
    }
}

private extension NSRegularExpression {
    func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: string, options: [], range: range)
    }
    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }
}
