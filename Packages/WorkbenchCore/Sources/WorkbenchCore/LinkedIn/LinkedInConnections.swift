import Foundation

/// One first-degree connection, as one row of the `Connections.csv` in a person's LinkedIn data export.
struct LinkedInConnection: Equatable {
    var name: String
    var profileURL: String
    var email: String?
    var company: String?
    var position: String?
    var connectedOn: String?

    /// The words of the row, in the order a person says them: who, what they do, how to reach them.
    var words: String {
        let work = [position, company.map { "at \($0)" }].compactMap { $0 }.joined(separator: " ")
        let connected = connectedOn.map { "connected on \($0)" }
        let head = [name, work.isEmpty ? nil : work].compactMap { $0 }.joined(separator: ", ")
        return ([head] + [connected, email, profileURL].compactMap { $0 }).joined(separator: ". ")
    }
}

/// Why a file is not a LinkedIn connections export. Each case says it in plain words.
enum LinkedInExportError: Error, Equatable, LocalizedError {
    case notText
    case noHeaderRow
    case noConnections

    var errorDescription: String? {
        switch self {
        case .notText: "This file is not text. Choose the Connections.csv file from your LinkedIn data export."
        case .noHeaderRow:
            "This file has no row with the columns \(LinkedInConnections.required.joined(separator: ", ")). "
                + "Choose the Connections.csv file from your LinkedIn data export."
        case .noConnections: "This file has the right columns but no connections. Nothing was changed."
        }
    }
}

/// The reader of `Connections.csv`. LinkedIn writes some note lines before the header row; the columns are found by
/// their header names, so their order and the optional ones do not matter.
enum LinkedInConnections {
    static let required = ["First Name", "Last Name", "URL"]
    private static let profileURLHeaders = ["URL", "LinkedIn URL"]

    /// The connections that have a profile URL, once each (the first row wins), and the count of rows without one.
    static func parse(_ file: Data) throws(LinkedInExportError) -> (connections: [LinkedInConnection], skipped: Int) {
        guard var text = String(data: file, encoding: .utf8) else { throw .notText }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let records = CSVRecords.parse(text)
        guard let headerIndex = records.firstIndex(where: { Columns($0) != nil }),
            let columns = Columns(records[headerIndex])
        else { throw .noHeaderRow }
        var seen: Set<String> = []
        var connections: [LinkedInConnection] = []
        var skipped = 0
        for record in records[(headerIndex + 1)...] where record.contains(where: { !$0.isEmpty }) {
            guard let url = columns.value("URL", in: record).map(normalized), !url.isEmpty else {
                skipped += 1
                continue
            }
            guard seen.insert(url).inserted else { continue }
            connections.append(
                LinkedInConnection(
                    name: [columns.value("First Name", in: record), columns.value("Last Name", in: record)]
                        .compactMap { $0 }.joined(separator: " "),
                    profileURL: url, email: columns.value("Email Address", in: record),
                    company: columns.value("Company", in: record), position: columns.value("Position", in: record),
                    connectedOn: columns.value("Connected On", in: record)))
        }
        guard !connections.isEmpty else { throw .noConnections }
        return (connections, skipped)
    }

    private static func normalized(_ url: String) -> String {
        var url = url
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    /// The positions of the named columns in a header row. Nil when the row lacks a required one.
    private struct Columns {
        let positions: [String: Int]

        init?(_ header: [String]) {
            var positions: [String: Int] = [:]
            for (index, name) in header.enumerated() { positions[name.trimmingCharacters(in: .whitespaces)] = index }
            positions["URL"] = LinkedInConnections.profileURLHeaders.lazy.compactMap { positions[$0] }.first
            guard LinkedInConnections.required.allSatisfy({ positions[$0] != nil }) else { return nil }
            self.positions = positions
        }

        /// A row's trimmed value of the column, nil when the row has none.
        func value(_ name: String, in record: [String]) -> String? {
            guard let index = positions[name], record.indices.contains(index) else { return nil }
            let value = record[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }
}
