import Foundation
import SQLite3

@main struct ResultExporterTests {
    static func tryJSON(_ value: String) -> Any? { try? JSONSerialization.jsonObject(with: Data(value.utf8)) }
    static func main() throws {
        let values: [CellValue] = [.null, .text(""), .text("00123"), .text("O'Brien\\path\n<>&\""), .blob(Data([0, 255])), .text("\0")]
        let columns = values.indices.map { ColumnInfo(name: "c\($0)", type: "TEXT") }
        let result = QueryResult(columns: columns, rows: [DataRow(cells: values)])
        let json = try ResultExporter(format: .json, sourceKind: .sqlite).encode(result)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let rows = parsed["rows"] as! [[Any]]
        precondition(rows[0][0] is NSNull && rows[0][1] as? String == "" && rows[0][2] as? String == "00123")
        precondition((rows[0][4] as? [String: String])?["base64"] == "AP8=")
        let csv = try ResultExporter(format: .csv, sourceKind: .sqlite).encode(QueryResult(columns: [ColumnInfo(name: "=header")], rows: [.init(cells: [.text(" \t=SUM(A1)")]), .init(cells: [.null]), .init(cells: [.text("")])]))
        precondition(csv.contains("\"'=header\"") && csv.contains("\"' \t=SUM(A1)\"") && csv.contains("\r\n\\N\r\n\"\"\r\n"))
        let yaml = try ResultExporter(format: .yaml, sourceKind: .sqlite).encode(result)
        precondition(tryJSON(yaml) != nil) // JSON syntax is also valid YAML 1.2.
        let txt = try ResultExporter(format: .txt, sourceKind: .sqlite).encode(result)
        precondition(txt.hasPrefix("\"c0\"\t\"c1\"") && txt.contains("\\N\t\"\""))
        let pgBinary = QueryResult(columns: [.init(name: "b", type: "OID 17")], rows: [.init(cells: [.text("\\x00ff5c")]), .init(cells: [.text("\\000\\377\\\\")])])
        let binaryJSON = try ResultExporter(format: .json, sourceKind: .postgresql).encode(pgBinary)
        let binaryRows = (try JSONSerialization.jsonObject(with: Data(binaryJSON.utf8)) as! [String: Any])["rows"] as! [[[String: String]]]
        precondition(binaryRows[0][0]["base64"] == "AP9c" && binaryRows[1][0]["base64"] == "AP9c")
        let xml = try ResultExporter(format: .xml, sourceKind: .sqlite).encode(result)
        precondition(XMLParser(data: Data(xml.utf8)).parse())
        precondition(xml.contains("null=\"true\"") && xml.contains("type=\"text\" encoding=\"base64\">AA==") && xml.contains("&lt;&gt;&amp;&quot;"))
        let sql = try ResultExporter(format: .sql, sourceKind: .sqlite, table: DatabaseObject(name: "t\"x")).encode(result)
        var db: OpaquePointer?
        precondition(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        precondition(sqlite3_exec(db, "CREATE TABLE \"t\"\"x\" (" + columns.map { quoteIdentifier($0.name) }.joined(separator: ",") + ")", nil, nil, nil) == SQLITE_OK)
        precondition(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "SELECT * FROM \"t\"\"x\"", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        precondition(sqlite3_step(statement) == SQLITE_ROW)
        precondition(sqlite3_column_type(statement, 0) == SQLITE_NULL)
        for index in 1...3 { precondition(String(cString: sqlite3_column_text(statement, Int32(index))) == values[index].string) }
        precondition(sqlite3_column_bytes(statement, 4) == 2 && sqlite3_column_type(statement, 4) == SQLITE_BLOB)
        precondition(sqlite3_column_bytes(statement, 5) == 1)
        let pg = try ResultExporter(format: .sql, sourceKind: .postgresql, sqlDialect: .postgresql, table: DatabaseObject(name: "t")).encode(QueryResult(columns: Array(columns.prefix(5)), rows: [.init(cells: Array(values.prefix(5)))]))
        precondition(pg.contains("decode('00ff', 'hex')") && pg.contains("E'O''Brien\\\\path"))
        do { _ = try ResultExporter(format: .sql, sourceKind: .postgresql, sqlDialect: .postgresql, table: DatabaseObject(name: "t")).encode(result); fatalError("NUL must fail") } catch is DatabaseFailure {}
        let document = "{\"_id\":{\"$oid\":\"000000000000000000000001\"},\"n\":{\"$numberLong\":\"9007199254740993\"}}"
        let mongo = QueryResult(columns: [], rows: [.init(cells: [], document: document)])
        let mongoJSON = try ResultExporter(format: .json, sourceKind: .mongodb).encode(mongo)
        precondition(mongoJSON == "[\n" + document + "\n]\n")
        do { _ = try ResultExporter(format: .sql, sourceKind: .mongodb, table: DatabaseObject(name: "t")).encode(mongo); fatalError("BSON SQL must fail") } catch is DatabaseFailure {}
        print("PASS: result exports; SQLite round trip; PostgreSQL escaping (static only); Mongo Extended JSON preservation")
    }
}
