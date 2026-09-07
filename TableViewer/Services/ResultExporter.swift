import Foundation

/// Exports the currently loaded result, never reruns a query or silently exports unseen pages.
enum ResultExportFormat: String, CaseIterable, Identifiable {
    case csv, txt, json, yaml, xml, sql
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var title: String { self == .sql ? "INSERT SQL" : rawValue.uppercased() }
}

enum ResultSQLDialect: String, CaseIterable, Identifiable {
    case sqlite = "SQLite", postgresql = "PostgreSQL"
    var id: String { rawValue }
}

struct ResultExporter {
    var format: ResultExportFormat
    var sourceKind: DatabaseKind
    var sqlDialect: ResultSQLDialect = .sqlite
    var table: DatabaseObject? = nil

    func encode(_ input: QueryResult) throws -> String {
        var result = input
        guard result.rows.allSatisfy({ $0.cells.count == result.columns.count }) else {
            throw DatabaseFailure("导出结果的列数与数据不一致。")
        }
        // libpq uses the text protocol; bytea has an authoritative OID/type name.
        // Decode only that type, never infer binary/numeric types from arbitrary text.
        if sourceKind == .postgresql {
            for row in result.rows.indices {
                for column in result.columns.indices where ["17", "oid 17", "bytea"].contains(result.columns[column].type.lowercased()) {
                    if case .text(let value) = result.rows[row].cells[column] {
                        result.rows[row].cells[column] = .blob(try postgresBinary(value))
                    }
                }
            }
        }
        switch format {
        case .csv, .txt:
            let separator = format == .csv ? "," : "\t"
            let header = result.columns.map { delimited($0.name) }.joined(separator: separator)
            let rows = result.rows.map { row in
                row.cells.map { cell in
                    switch cell {
                    case .null: return "\\N"
                    case .text(let value): return delimited(value)
                    case .blob(let data): return delimited("base64:" + data.base64EncodedString())
                    }
                }.joined(separator: separator)
            }
            return ([header] + rows).joined(separator: "\r\n") + "\r\n"
        case .json, .yaml:
            if sourceKind == .mongodb {
                // Keep the driver's original Extended JSON bytes, including numeric precision
                // and BSON markers. Foundation parsing is validation only, never serialization.
                let documents = try result.rows.map { row -> String in
                    guard let document = row.document,
                          (try? JSONSerialization.jsonObject(with: Data(document.utf8))) is [String: Any] else {
                        throw DatabaseFailure("MongoDB JSON 导出需要完整的原始文档。")
                    }
                    return document
                }
                return "[\n" + documents.joined(separator: ",\n") + "\n]\n"
            }
            return try jsonText(tabularObject(result), pretty: true) + "\n"
        case .xml:
            let columns = result.columns.map { "    <column name=\"\(xml($0.name))\" type=\"\(xml($0.type))\"/>" }.joined(separator: "\n")
            let rows = result.rows.map { row in
                "    <row>\n" + row.cells.map { cell in
                    switch cell {
                    case .null: return "      <cell null=\"true\"/>"
                    case .blob(let data): return "      <cell type=\"blob\" encoding=\"base64\">\(data.base64EncodedString())</cell>"
                    case .text(let value):
                        if !validXML(value) { return "      <cell type=\"text\" encoding=\"base64\">\(Data(value.utf8).base64EncodedString())</cell>" }
                        return "      <cell type=\"text\" xml:space=\"preserve\">\(xml(value))</cell>"
                    }
                }.joined(separator: "\n") + "\n    </row>"
            }.joined(separator: "\n")
            guard result.columns.allSatisfy({ validXML($0.name) && validXML($0.type) }) else {
                throw DatabaseFailure("列名或类型包含 XML 无法表示的字符，请使用 JSON 导出。")
            }
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<result>\n  <columns>\n\(columns)\n  </columns>\n  <rows>\n\(rows)\n  </rows>\n</result>\n"
        case .sql:
            guard sourceKind != .mongodb else { throw DatabaseFailure("MongoDB 文档不能直接导出为关系数据库 INSERT，请使用 JSON。") }
            guard let table, !table.name.isEmpty, !table.name.contains("\0"), !table.schema.contains("\0"),
                  !result.columns.isEmpty,
                  Set(result.columns.map(\.name)).count == result.columns.count,
                  result.columns.allSatisfy({ !$0.name.contains("\0") }) else {
                throw DatabaseFailure("INSERT 导出需要目标表名和不重复的有效列名。")
            }
            let columns = result.columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
            let statements = try result.rows.map { row in
                "INSERT INTO \(table.qualifiedName) (\(columns)) VALUES (\(try row.cells.map(sqlValue).joined(separator: ", ")));"
            }
            return "-- \(sqlDialect.rawValue) INSERT; target table must already exist.\n-- Text driver values remain quoted; target schema determines conversion.\n" + statements.joined(separator: "\n") + "\n"
        }
    }

    private func postgresBinary(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        var output = Data()
        if bytes.starts(with: [92, 120]) {
            guard (bytes.count - 2).isMultiple(of: 2) else { throw DatabaseFailure("PostgreSQL bytea 数据格式无效。") }
            for index in stride(from: 2, to: bytes.count, by: 2) {
                guard let byte = UInt8(String(decoding: bytes[index...index + 1], as: UTF8.self), radix: 16) else { throw DatabaseFailure("PostgreSQL bytea 数据格式无效。") }
                output.append(byte)
            }
        } else {
            var index = 0
            while index < bytes.count {
                if bytes[index] != 92 { output.append(bytes[index]); index += 1; continue }
                if index + 1 < bytes.count, bytes[index + 1] == 92 { output.append(92); index += 2; continue }
                guard index + 3 < bytes.count, bytes[index + 1...index + 3].allSatisfy({ (48...55).contains($0) }),
                      let byte = UInt8(String(decoding: bytes[index + 1...index + 3], as: UTF8.self), radix: 8) else {
                    throw DatabaseFailure("PostgreSQL bytea 数据格式无效。")
                }
                output.append(byte); index += 4
            }
        }
        return output
    }

    private func tabularObject(_ result: QueryResult) -> [String: Any] {
        ["columns": result.columns.map { ["name": $0.name, "databaseType": $0.type] },
         "rows": result.rows.map { row in row.cells.map { cell -> Any in
             switch cell {
             case .null: return NSNull()
             case .text(let value): return value
             case .blob(let data): return ["type": "blob", "base64": data.base64EncodedString()]
             }
         } }]
    }

    private func delimited(_ value: String) -> String {
        // Spreadsheet formula mitigation applies to headers and values, including leading
        // whitespace/control prefixes. JSON/XML/SQL remain exact, machine-readable exports.
        let significant = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let risky = significant.first.map { "=+-@".contains($0) } == true || value.first == "\t" || value.first == "\r" || value.first == "\n"
        let safe = risky ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func sqlValue(_ cell: CellValue) throws -> String {
        switch cell {
        case .null: return "NULL"
        case .blob(let data):
            let hex = data.map { String(format: "%02x", $0) }.joined()
            return sqlDialect == .sqlite ? "X'\(hex)'" : "decode('\(hex)', 'hex')"
        case .text(let value):
            if value.contains("\0") {
                guard sqlDialect == .sqlite else { throw DatabaseFailure("PostgreSQL text 不支持 NUL 字符，无法无损导出该值。") }
                return "CAST(X'\(Data(value.utf8).map { String(format: "%02x", $0) }.joined())' AS TEXT)"
            }
            let escaped = value.replacingOccurrences(of: "'", with: "''")
            return sqlDialect == .sqlite ? "'\(escaped)'" : "E'\(escaped.replacingOccurrences(of: "\\", with: "\\\\"))'"
        }
    }

    private func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;").replacingOccurrences(of: "\r", with: "&#13;")
            .replacingOccurrences(of: "\n", with: "&#10;").replacingOccurrences(of: "\t", with: "&#9;")
    }
    private func validXML(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            let n = scalar.value
            return n == 9 || n == 10 || n == 13 || (0x20...0xD7FF).contains(n) || (0xE000...0xFFFD).contains(n) || (0x10000...0x10FFFF).contains(n)
        }
    }
}
