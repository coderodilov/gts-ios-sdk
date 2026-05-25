import Foundation

public struct GtsResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data
    public let json: JSONValue?
    public let authMode: String

    public var isSuccessful: Bool {
        (200...299).contains(statusCode)
    }

    public var text: String {
        String(data: data, encoding: .utf8) ?? ""
    }

    public var compactError: String {
        let text = text
        if let value = text.htmlPreValue(cssClass: "exception_value") {
            return value
        }
        if let type = text.htmlPreValue(cssClass: "exception_type") {
            return type
        }
        return text.cleaningHtml().prefixString(800)
    }
}

extension String {
    func prefixString(_ maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength))
    }

    func cleaningHtml() -> String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func htmlPreValue(cssClass: String) -> String? {
        let pattern = #"<pre class="\#(cssClass)">(.*?)</pre>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: nsRange),
              let range = Range(match.range, in: self) else {
            return nil
        }
        return String(self[range]).cleaningHtml().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
