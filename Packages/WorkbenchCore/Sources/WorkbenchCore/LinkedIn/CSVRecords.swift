/// The records of a CSV text (RFC 4180): a quoted field can hold commas, line breaks and doubled quotes.
enum CSVRecords {
    static func parse(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var isQuoted = false
        var wasQuoted = false
        var characters = text.unicodeScalars.makeIterator()
        var next = characters.next()

        func endField() {
            record.append(field)
            field = ""
            wasQuoted = false
        }
        func endRecord() {
            endField()
            records.append(record)
            record = []
        }

        while let scalar = next {
            next = characters.next()
            switch (scalar, isQuoted) {
            case ("\"", true) where next == "\"":
                field.unicodeScalars.append("\"")
                next = characters.next()
            case ("\"", true): isQuoted = false
            case ("\"", false) where field.isEmpty && !wasQuoted:
                isQuoted = true
                wasQuoted = true
            case (",", false): endField()
            case ("\r", false) where next == "\n": continue
            case ("\n", false), ("\r", false): endRecord()
            default: field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !record.isEmpty || wasQuoted { endRecord() }
        return records
    }
}
