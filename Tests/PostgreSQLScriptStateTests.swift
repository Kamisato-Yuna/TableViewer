import Foundation

@main struct PostgreSQLScriptStateTests {
    static func main() throws {
        let port = ProcessInfo.processInfo.environment["TABLEVIEWER_TEST_PG_PORT"] ?? "32850"
        guard let db = PQconnectdb("host=127.0.0.1 port=\(port) dbname=acceptance040 user=postgres connect_timeout=5"), PQstatus(db) == CONNECTION_OK else { fatalError("synthetic PostgreSQL unavailable") }
        defer { PQfinish(db) }
        let schema = "script_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        func run(_ query: String) throws -> String? {
            guard let result = PQexecParams(db, query, 0, nil, nil, nil, nil, 0) else { throw DatabaseFailure("No PostgreSQL result") }
            defer { PQclear(result) }
            guard [PGRES_COMMAND_OK, PGRES_TUPLES_OK].contains(PQresultStatus(result)) else { throw DatabaseFailure(String(cString: PQresultErrorMessage(result))) }
            return PQntuples(result) > 0 ? String(cString: PQgetvalue(result, 0, 0)) : nil
        }
        _ = try run("CREATE SCHEMA " + quoteIdentifier(schema))
        defer { _ = try? run("DROP SCHEMA " + quoteIdentifier(schema) + " CASCADE") }
        func execute(_ script: String) throws -> [String] {
            var remaining = script, rows: [String] = []
            while true {
                guard let setting = PQparameterStatus(db, "standard_conforming_strings") else { throw DatabaseFailure("Missing setting") }
                let standard = String(cString: setting) == "on"
                guard let next = try SQLScript.nextPostgreSQLStatement(remaining, standardConformingStrings: standard) else { break }
                remaining = next.remainder
                if let value = try run(next.statement) { rows.append(value) }
            }
            return rows
        }
        let values = try execute(#"SET standard_conforming_strings=off; SELECT 'a\';b'; SET standard_conforming_strings=on; SELECT E'a\';b'; SELECT 'a\';"#)
        precondition(values == ["a';b", "a';b", "a\\"])
        let function = quoteIdentifier(schema) + ".f"
        let atomic = try execute("CREATE FUNCTION \(function)() RETURNS integer LANGUAGE SQL BEGIN ATOMIC SELECT CASE WHEN true THEN CASE WHEN false THEN 1 ELSE 2 END ELSE 3 END; SELECT 7; END; SELECT \(function)();")
        precondition(atomic == ["7"])
        let configured = try execute(#"SELECT set_config('standard_conforming_strings', 'off', false); SELECT 'x\';y';"#)
        precondition(configured == ["off", "x';y"])
        let table = quoteIdentifier(schema) + ".t"
        do { _ = try execute("CREATE TABLE \(table)(n int); INSERT INTO \(table) VALUES(1); INVALID QUERY; INSERT INTO \(table) VALUES(2);"); fatalError("Expected native SQL failure") }
        catch is DatabaseFailure {}
        let count = try run("SELECT count(*) FROM \(table)")
        precondition(count == "1")
        print("PASS real PostgreSQL per-statement setting refresh, plain/E strings, BEGIN ATOMIC/CASE, stop on failure; UUID schema cleaned")
    }
}
