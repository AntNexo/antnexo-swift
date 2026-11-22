/// A locale identifier as BCP 47 (`en_CZ` → `en-CZ`), without `@` keywords, at most 35 characters (the API's limit).
public func bcp47(_ identifier: String) -> String {
    let base = identifier.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
    let tag = base.replacingOccurrences(of: "_", with: "-")
    return tag.isEmpty ? "und" : String(tag.prefix(35))
}
