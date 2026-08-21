import Foundation

/// What pressing Return should do on a line, matching Obsidian's behaviour:
/// a list carries on by itself, and an empty item ends the list instead of adding another.
enum ListContinuation {
    enum Outcome: Equatable {
        /// Not a list line -- insert a plain newline.
        case plain
        /// Insert a newline followed by this prefix.
        case carryOn(String)
        /// The item is empty: strip this many leading characters and stay put.
        case endList(prefixLength: Int)
    }

    private static let marker = try! NSRegularExpression(
        pattern: "^([ \t]*)(?:([-*+])|([0-9]+)([.)]))[ \t]+(\\[[ xX]\\][ \t]+)?")
    private static let quote = try! NSRegularExpression(
        pattern: "^([ \t]*>[ \t]?)")

    /// `caret` is the offset of the insertion point within `line`.
    static func outcome(for line: String, caret: Int) -> Outcome {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)

        if let match = marker.firstMatch(in: line, options: [], range: whole) {
            let prefixLength = match.range.length
            // Caret still inside the marker itself -- let Return behave normally.
            guard caret >= prefixLength else { return .plain }

            let rest = ns.substring(from: prefixLength).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return .endList(prefixLength: prefixLength) }

            let indent = ns.substring(with: match.range(at: 1))
            let isTask = match.range(at: 5).location != NSNotFound
            let task = isTask ? "[ ] " : ""

            if match.range(at: 2).location != NSNotFound {
                return .carryOn(indent + ns.substring(with: match.range(at: 2)) + " " + task)
            }
            // Ordered lists count up, the way Obsidian does.
            let number = Int(ns.substring(with: match.range(at: 3))) ?? 0
            let delimiter = ns.substring(with: match.range(at: 4))
            return .carryOn(indent + "\(number + 1)" + delimiter + " " + task)
        }

        if let match = quote.firstMatch(in: line, options: [], range: whole) {
            let prefixLength = match.range.length
            guard caret >= prefixLength else { return .plain }
            let rest = ns.substring(from: prefixLength).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return .endList(prefixLength: prefixLength) }
            return .carryOn(ns.substring(with: match.range(at: 1)))
        }

        return .plain
    }
}
