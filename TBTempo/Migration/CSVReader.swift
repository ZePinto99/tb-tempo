import Foundation

enum CSVError: LocalizedError {
    case invalidEncoding
    case malformedRow(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: String(localized: "A CSV file is not valid UTF-8.")
        case .malformedRow(let row): String(localized: "A CSV row is malformed near row \(row).")
        }
    }
}

struct CSVReader {
    static func rows(data: Data) throws -> [[String: String]] {
        guard var text = String(data: data, encoding: .utf8) else { throw CSVError.invalidEncoding }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let records = parse(text)
        guard let header = records.first else { return [] }
        return records.dropFirst().enumerated().compactMap { _, values in
            guard !values.allSatisfy(\.isEmpty) else { return nil }
            var row: [String: String] = [:]
            for (index, key) in header.enumerated() {
                row[key] = index < values.count ? values[index] : ""
            }
            return row
        }
    }

    private static func parse(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        func finishField() {
            record.append(field)
            field = ""
        }
        func finishRecord() {
            finishField()
            records.append(record)
            record = []
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                finishField()
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" { index = next }
                }
                finishRecord()
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !record.isEmpty { finishRecord() }
        return records
    }
}
