import Foundation

/// Fuzzy search over the symbol catalog.
///
/// Matching is subsequence-based, so "grsgl" finds "Größer gleich" and "intgrl"
/// finds "Integral" — you rarely have to know the exact wording, let alone the
/// LaTeX command.
enum SymbolSearch {

    /// Normalises umlauts and case so German spelling never blocks a match.
    static func fold(_ string: String) -> String {
        var result = string.lowercased()
        let replacements = ["ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss"]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result.folding(options: [.diacriticInsensitive], locale: .init(identifier: "de_DE"))
    }

    /// `nil` when the candidate does not match at all; higher is better.
    static func score(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let haystack = Array(fold(candidate))
        let needle = Array(fold(query))
        guard !haystack.isEmpty, needle.count <= haystack.count else { return nil }

        if haystack == needle { return 1_000 }

        var score = 0
        var haystackIndex = 0
        var lastMatch = -1
        var consecutive = 0

        for character in needle {
            var found = false
            while haystackIndex < haystack.count {
                defer { haystackIndex += 1 }
                guard haystack[haystackIndex] == character else { continue }

                if haystackIndex == lastMatch + 1 {
                    consecutive += 1
                    score += 12 + consecutive * 3   // runs of adjacent letters are strong evidence
                } else {
                    consecutive = 0
                    score += 6
                }
                if haystackIndex == 0 { score += 40 }                       // matches the start
                else if haystack[haystackIndex - 1] == " " { score += 18 }  // matches a word start
                score -= min(haystackIndex - lastMatch - 1, 8)              // penalise big gaps

                lastMatch = haystackIndex
                found = true
                break
            }
            if !found { return nil }
        }

        // Shorter candidates that match are usually the ones you meant.
        score -= haystack.count / 6
        return score
    }

    /// Best score across everything the symbol can be found by.
    static func score(query: String, symbol: MathSymbol) -> Int? {
        var best: Int?
        for (index, field) in symbol.searchCorpus.enumerated() {
            guard let value = score(query: query, candidate: field) else { continue }
            // The display name counts for more than a stray keyword.
            let weighted = index == 0 ? value + 25 : value
            if best == nil || weighted > best! { best = weighted }
        }
        return best
    }

    static func search(_ query: String,
                       in symbols: [MathSymbol] = SymbolCatalog.all,
                       category: SymbolCategory? = nil,
                       limit: Int = 200) -> [MathSymbol] {
        let pool = category.map { cat in symbols.filter { $0.category == cat } } ?? symbols
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(pool.prefix(limit)) }

        return pool
            .compactMap { symbol -> (MathSymbol, Int)? in
                guard let value = score(query: trimmed, symbol: symbol) else { return nil }
                return (symbol, value)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}

/// Remembers which symbols the user actually reaches for, so the palette is
/// useful before a single character is typed.
@MainActor
enum RecentSymbols {
    private static let key = "MathPad.recentSymbols"
    private static let maximum = 24

    static func record(_ symbol: MathSymbol) {
        var ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        ids.removeAll { $0 == symbol.id }
        ids.insert(symbol.id, at: 0)
        UserDefaults.standard.set(Array(ids.prefix(maximum)), forKey: key)
    }

    static func symbols() -> [MathSymbol] {
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        let index = Dictionary(SymbolCatalog.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { index[$0] }
    }
}
