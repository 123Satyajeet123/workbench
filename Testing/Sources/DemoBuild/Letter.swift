import Foundation

/// One synthetic mail, read from an `.eml` file: who wrote it, who got it, when, the words and the attached decks.
struct Letter: Equatable {
    struct Attachment: Equatable {
        let name: String
        let data: Data
    }

    /// The thread is the startup's id (`S13`); the message id is the file's id (`S13-m2`).
    let thread: String
    let message: String
    let sender: String
    let recipients: [String]
    let sent: Date
    let text: String
    let quoted: String?
    let attachments: [Attachment]
}

enum LetterError: Error, Equatable {
    case notAMail(String)
}

/// Reads RFC 822 text. It knows only what the synthetic mails use: folded headers, one level of multipart, quoted-printable
/// and base64 bodies, and a date in the form `Fri, 06 Nov 2026 09:59:27 +0530`.
enum LetterParser {
    static func parse(_ data: Data) throws -> Letter {
        let (headers, body) = try split(data)
        guard let from = headers["from"], let date = headers["date"].flatMap(Self.date),
            let id = headers["message-id"].map(Self.messageID), let thread = id.split(separator: "-").first
        else { throw LetterError.notAMail("the headers lack From, Date or Message-ID") }
        let parts = try Self.parts(headers: headers, body: body)
        let words = parts.first { $0.type == "text/plain" && $0.filename == nil }?.text ?? ""
        let (text, quoted) = unquoted(words)
        return Letter(
            thread: String(thread), message: id, sender: addresses(from)[0],
            recipients: addresses((headers["to"] ?? "") + "," + (headers["cc"] ?? "")), sent: date, text: text,
            quoted: quoted,
            attachments: parts.compactMap { part in part.filename.map { Letter.Attachment(name: $0, data: part.data) } }
        )
    }

    private struct Part {
        let type: String
        let filename: String?
        let data: Data
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    private static func parts(headers: [String: String], body: Data) throws -> [Part] {
        let type = headers["content-type"] ?? "text/plain"
        guard type.lowercased().hasPrefix("multipart/"), let boundary = parameter("boundary", in: type) else {
            return [try part(headers: headers, body: body)]
        }
        let marker = Data("--\(boundary)".utf8)
        return try chunks(of: body, separatedBy: marker).dropFirst().compactMap { chunk in
            guard !chunk.starts(with: Data("--".utf8)) else { return nil }
            let (headers, body) = try split(chunk.drop(while: { $0 == 10 || $0 == 13 }))
            return try part(headers: headers, body: body)
        }
    }

    private static func part(headers: [String: String], body: Data) throws -> Part {
        let type = (headers["content-type"] ?? "text/plain").split(separator: ";")[0].lowercased()
        let disposition = headers["content-disposition"] ?? ""
        let filename = parameter("filename", in: disposition) ?? parameter("name", in: headers["content-type"] ?? "")
        let encoding = (headers["content-transfer-encoding"] ?? "7bit").lowercased()
        let data: Data
        switch encoding {
        case "quoted-printable": data = quotedPrintable(body)
        case "base64":
            let packed = String(decoding: body, as: UTF8.self).filter { !$0.isWhitespace }
            guard let decoded = Data(base64Encoded: packed) else { throw LetterError.notAMail("bad base64") }
            data = decoded
        default: data = body
        }
        return Part(type: type, filename: filename, data: data)
    }

    private static func split(_ data: some DataProtocol) throws -> (headers: [String: String], body: Data) {
        let bytes = Data(data)
        let crlf = Data("\r\n\r\n".utf8)
        let lf = Data("\n\n".utf8)
        let gap = [crlf, lf].compactMap { bytes.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        guard let gap else { throw LetterError.notAMail("no blank line after the headers") }
        let head = String(decoding: bytes[..<gap.lowerBound], as: UTF8.self)
        var headers: [String: String] = [:]
        var last: String?
        for line in head.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if line.first?.isWhitespace == true, let key = last {
                headers[key, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].lowercased()
                headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                last = key
            }
        }
        return (headers.mapValues(decodedWords), Data(bytes[gap.upperBound...]))
    }

    private static func chunks(of data: Data, separatedBy marker: Data) -> [Data] {
        var result: [Data] = []
        var rest = data[...]
        while let found = rest.range(of: marker) {
            result.append(Data(rest[..<found.lowerBound]))
            rest = rest[found.upperBound...]
        }
        result.append(Data(rest))
        return result
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        let pattern = try? Regex("\(name)=(?:\"([^\"]*)\"|([^;\\s]+))").ignoresCase()
        guard let match = try? pattern?.firstMatch(in: header) else { return nil }
        return (match.output[1].substring ?? match.output[2].substring).map(String.init)
    }

    /// `=?utf-8?q?...?=` words of a header, as the synthetic subjects use them.
    private static func decodedWords(_ header: String) -> String {
        header.replacing(/=\?utf-8\?([qQbB])\?([^?]*)\?=/) { match in
            if match.output.1.lowercased() == "b" {
                return Data(base64Encoded: String(match.output.2)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            }
            return String(
                decoding: quotedPrintable(Data(match.output.2.replacingOccurrences(of: "_", with: " ").utf8)),
                as: UTF8.self)
        }
    }

    static func quotedPrintable(_ body: Data) -> Data {
        var out = Data()
        let lines = String(decoding: body, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            var line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            let isSoft = line.hasSuffix("=")
            if isSoft { line = line.dropLast() }
            var bytes = Array(line.utf8)[...]
            while let byte = bytes.popFirst() {
                if byte == UInt8(ascii: "="), bytes.count >= 2,
                    let value = UInt8(String(decoding: bytes.prefix(2), as: UTF8.self), radix: 16)
                {
                    out.append(value)
                    bytes = bytes.dropFirst(2)
                } else {
                    out.append(byte)
                }
            }
            if !isSoft, index < lines.count - 1 { out.append(10) }
        }
        return out
    }

    private static func addresses(_ header: String) -> [String] {
        header.split(separator: ",").compactMap { entry in
            let text = String(entry)
            if let open = text.firstIndex(of: "<"), let close = text.firstIndex(of: ">"), open < close {
                return String(text[text.index(after: open)..<close]).lowercased()
            }
            let bare = text.trimmingCharacters(in: .whitespaces)
            return bare.contains("@") ? bare.lowercased() : nil
        }
    }

    private static func messageID(_ header: String) -> String {
        let bare = header.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        return String(bare.split(separator: "@")[0])
    }

    private static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: text)
    }

    /// Lines that start with `>` are the quoted part of a reply; the rest is what the sender wrote.
    private static func unquoted(_ words: String) -> (text: String, quoted: String?) {
        let lines = words.split(separator: "\n", omittingEmptySubsequences: false)
        let quoted = lines.filter { $0.hasPrefix(">") }.map { $0.dropFirst().trimmingCharacters(in: .whitespaces) }
        let own = lines.filter { !$0.hasPrefix(">") }.joined(separator: "\n")
        return (
            own.trimmingCharacters(in: .whitespacesAndNewlines), quoted.isEmpty ? nil : quoted.joined(separator: "\n")
        )
    }
}
