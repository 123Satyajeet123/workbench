import Foundation

/// The visible text of an HTML page: no scripts, styles or tags, entities decoded, white space made single spaces.
public enum HTMLText {
    nonisolated(unsafe) private static let hidden =
        #/(?is)<(script|style|noscript|svg|template)\b.*?</\1\s*>|<!--.*?-->/#
    nonisolated(unsafe) private static let tag = #/(?s)<[^>]*>/#
    nonisolated(unsafe) private static let blockBreak =
        #/(?i)</?(p|div|br|li|ul|ol|h[1-6]|tr|table|section|article|header|footer)\b[^>]*>/#
    nonisolated(unsafe) private static let entity = #/&(#x?[0-9A-Fa-f]+|[A-Za-z]+);/#
    private static let named = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
        "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "hellip": "…", "rupee": "₹",
    ]

    public static func plain(_ html: String) -> String {
        let visible = html.replacing(hidden, with: " ").replacing(blockBreak, with: " ").replacing(tag, with: " ")
        let decoded = visible.replacing(entity) { match in decode(String(match.1)) ?? String(match.0) }
        return decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func decode(_ name: String) -> String? {
        guard name.hasPrefix("#") else { return named[name] }
        let digits = name.dropFirst()
        let code =
            digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
        return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }
}
