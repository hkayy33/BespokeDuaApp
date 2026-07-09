import Foundation

struct DuaTextSegment: Identifiable, Equatable {
    enum Kind: Equatable {
        case editable
        case lockedName
    }

    let id: UUID
    var kind: Kind
    var content: String

    var isLocked: Bool { kind == .lockedName }

    init(id: UUID = UUID(), kind: Kind, content: String) {
        self.id = id
        self.kind = kind
        self.content = content
    }
}

/// Splits bespoke dua text into editable surrounding text and locked divine-name segments.
enum DuaTextSegments {
    private static let arabicParentheticalPattern = #"^\s*\([\u0600-\u06FF\s]+\)"#

    static func parse(duaText: String, explanations: [ExplanationModel]) -> [DuaTextSegment] {
        let divineNames = divineNameExplanations(explanations)

        var matches: [(Range<String.Index>, String)] = []
        for explanation in divineNames {
            if let range = findNameRange(in: duaText, explanationName: explanation.name) {
                matches.append((range, String(duaText[range])))
            }
        }

        if !divineNames.isEmpty {
            for range in findYaNameRanges(in: duaText) {
                let lockedText = String(duaText[range])
                if !matches.contains(where: { $0.1.caseInsensitiveCompare(lockedText) == .orderedSame }) {
                    matches.append((range, lockedText))
                }
            }
        }

        matches.sort { $0.0.lowerBound < $1.0.lowerBound }
        let nonOverlapping = removeOverlapping(matches)

        guard !nonOverlapping.isEmpty else {
            return [DuaTextSegment(kind: .editable, content: duaText)]
        }

        var segments: [DuaTextSegment] = []
        var cursor = duaText.startIndex

        for (range, _) in nonOverlapping {
            let lockedRange = extendLockedNameRange(in: duaText, range: range)
            let lockedText = String(duaText[lockedRange])

            if cursor < lockedRange.lowerBound {
                segments.append(DuaTextSegment(kind: .editable, content: String(duaText[cursor..<lockedRange.lowerBound])))
            }
            segments.append(DuaTextSegment(kind: .lockedName, content: lockedText))
            cursor = lockedRange.upperBound
        }

        if cursor < duaText.endIndex {
            segments.append(DuaTextSegment(kind: .editable, content: String(duaText[cursor...])))
        }

        let normalized = attachFollowingPunctuation(to: segments)
        return normalized.isEmpty ? [DuaTextSegment(kind: .editable, content: duaText)] : normalized
    }

    static func assemble(_ segments: [DuaTextSegment]) -> String {
        segments.map(\.content).joined()
    }

    static func lockedSegmentsIntact(originalLocked: [String], in edited: [DuaTextSegment]) -> Bool {
        let currentLocked = edited.filter(\.isLocked).map(\.content)
        return currentLocked == originalLocked
    }

    static func lockedTextsIntact(originalLocked: [String], in text: String) -> Bool {
        guard !originalLocked.isEmpty else { return true }

        var searchStart = text.startIndex
        for locked in originalLocked {
            guard let range = text.range(of: locked, range: searchStart..<text.endIndex) else {
                return false
            }
            searchStart = range.upperBound
        }
        return true
    }

    // MARK: - Private

    private static func divineNameExplanations(_ explanations: [ExplanationModel]) -> [ExplanationModel] {
        explanations.filter { explanation in
            let lower = explanation.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !lower.isEmpty && lower != "source"
        }
    }

    private static func removeOverlapping(_ matches: [(Range<String.Index>, String)]) -> [(Range<String.Index>, String)] {
        var result: [(Range<String.Index>, String)] = []
        var lastEnd: String.Index?

        for match in matches {
            if let end = lastEnd, match.0.lowerBound < end {
                continue
            }
            result.append(match)
            lastEnd = match.0.upperBound
        }

        return result
    }

    private static func findNameRange(in text: String, explanationName: String) -> Range<String.Index>? {
        let variants = searchVariants(for: explanationName)
        var best: Range<String.Index>?

        for variant in variants {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                      of: variant,
                      options: [.caseInsensitive],
                      range: searchStart..<text.endIndex
                  ) {
                let extended = extendLockedNameRange(in: text, range: range)
                if best == nil || extended.lowerBound < best!.lowerBound {
                    best = extended
                }
                searchStart = range.upperBound
            }
        }

        return best
    }

    private static func searchVariants(for explanationName: String) -> [String] {
        let trimmed = explanationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var variants: [String] = [trimmed]
        let prefixes = ["Al-", "Ar-", "As-", "At-", "Ad-", "An-"]

        for prefix in prefixes where trimmed.hasPrefix(prefix) {
            let withoutPrefix = String(trimmed.dropFirst(prefix.count))
            variants.append("Ya \(withoutPrefix)")
            variants.append(withoutPrefix)
            break
        }

        let withoutHyphens = trimmed.replacingOccurrences(of: "-", with: " ")
        if withoutHyphens != trimmed {
            variants.append(withoutHyphens)
            variants.append("Ya \(withoutHyphens)")
        }

        let compact = trimmed.replacingOccurrences(of: "-", with: "")
        if compact != trimmed {
            variants.append(compact)
            variants.append("Ya \(compact)")
        }

        if !trimmed.lowercased().hasPrefix("ya ") {
            variants.append("Ya \(trimmed)")
        }

        return Array(Set(variants)).sorted { $0.count > $1.count }
    }

    private static func findYaNameRanges(in text: String) -> [Range<String.Index>] {
        let pattern = #"\bYa\s+[A-Za-z][A-Za-z'\s-]*(?:\s*\([\u0600-\u06FF\s]+\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        return matches.compactMap { match in
            Range(match.range, in: text)
        }
    }

    private static func extendWithArabicParenthetical(in text: String, range: Range<String.Index>) -> Range<String.Index> {
        let remainder = text[range.upperBound...]
        guard let match = remainder.range(of: arabicParentheticalPattern, options: .regularExpression) else {
            return range
        }
        return range.lowerBound..<match.upperBound
    }

    /// Keeps commas and similar punctuation glued to the divine name backdrop.
    private static func extendLockedNameRange(in text: String, range: Range<String.Index>) -> Range<String.Index> {
        var end = extendWithArabicParenthetical(in: text, range: range).upperBound
        guard end < text.endIndex else { return range.lowerBound..<end }

        var index = end
        while index < text.endIndex, text[index].isWhitespace {
            let next = text.index(after: index)
            guard next < text.endIndex, isNameTrailingPunctuation(text[next]) else { break }
            index = text.index(after: index)
        }

        while index < text.endIndex, isNameTrailingPunctuation(text[index]) {
            index = text.index(after: index)
        }

        return range.lowerBound..<index
    }

    private static func isNameTrailingPunctuation(_ character: Character) -> Bool {
        ",.;:!?،؛".contains(character)
    }

    /// Moves leading punctuation from editable segments onto the preceding locked name.
    private static func attachFollowingPunctuation(to segments: [DuaTextSegment]) -> [DuaTextSegment] {
        var result = segments
        var index = 0

        while index < result.count {
            guard result[index].isLocked,
                  index + 1 < result.count,
                  result[index + 1].kind == .editable else {
                index += 1
                continue
            }

            var editable = result[index + 1].content
            var attached = ""

            while editable.first?.isWhitespace == true {
                let nextIndex = editable.index(after: editable.startIndex)
                guard nextIndex < editable.endIndex,
                      isNameTrailingPunctuation(editable[nextIndex]) else { break }
                attached.append(editable.removeFirst())
            }

            while let first = editable.first, isNameTrailingPunctuation(first) {
                attached.append(editable.removeFirst())
            }

            guard !attached.isEmpty else {
                index += 1
                continue
            }

            result[index].content += attached
            if editable.isEmpty {
                result.remove(at: index + 1)
            } else {
                result[index + 1].content = editable
            }
        }

        return result
    }
}
