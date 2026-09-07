import Foundation

@main struct SQLScriptBoundaryReview {
    static func main() throws {
        let cases: [(String, DatabaseKind, String, Int)] = [
            ("PG atomic function", .postgresql, "CREATE FUNCTION f() RETURNS int LANGUAGE SQL BEGIN ATOMIC SELECT 1; SELECT 2; END; SELECT 3;", 2),
            ("PG atomic CASE nesting", .postgresql, "CREATE FUNCTION f() RETURNS int LANGUAGE SQL BEGIN /*block*/ ATOMIC SELECT CASE WHEN true THEN CASE WHEN false THEN 1 ELSE 2 END ELSE 3 END; SELECT 'END; BEGIN ATOMIC'; END; SELECT 3;", 2),
            ("PG atomic quoted identifier", .postgresql, "CREATE FUNCTION f() RETURNS int LANGUAGE SQL BEGIN ATOMIC SELECT 1 AS \"END\"; END; SELECT 3;", 2),
            ("PG emoji dollar quote", .postgresql, "SELECT $🌊$hello; world$🌊$; SELECT 2;", 2),
            ("PG dollar quote", .postgresql, "DO $body$ BEGIN RAISE NOTICE 'hello;'; END $body$; SELECT 2;", 2),
            ("PG Unicode dollar quote", .postgresql, "SELECT $日本語$hello; world$日本語$; SELECT 2;", 2),
            ("PG escape string", .postgresql, #"SELECT E'abc\';def'; SELECT 2;"#, 2),
            ("PG nested comment only", .postgresql, "/* outer /* inner */ SELECT */;", 0),
            ("PG nested block comments", .postgresql, "SELECT 1 /* outer /* ; inner */ ; outer */; SELECT 2;", 2),
            ("PG CR line comment", .postgresql, "SELECT 1; -- comment\rSELECT 2; SELECT 3;", 3),
            ("PG CRLF line comment", .postgresql, "SELECT 1; -- comment\r\nSELECT 2; SELECT 3;", 3),
            ("PG Unicode identifier", .postgresql, "SELECT \"列;名\", '🌊;流萤'; SELECT 2;", 2),
            ("SQLite trigger", .sqlite, "CREATE TRIGGER log AFTER INSERT ON source BEGIN INSERT INTO audit VALUES('a;'); UPDATE audit SET x=CASE WHEN x='a;' THEN 'b;' ELSE x END; END; SELECT 2;", 2),
            ("SQLite unclosed comment", .sqlite, "SELECT 1; /* unfinished", 1),
            ("SQLite final no semicolon", .sqlite, "SELECT '🌊;'; SELECT 2", 2),
            ("SQLite CRLF comment", .sqlite, "SELECT 1; -- comment\r\nSELECT 2; SELECT 3;", 3),
            ("PG failed statement boundary", .postgresql, "INSERT INTO t VALUES(1); INVALID SQL; DELETE FROM t;", 3)
        ]
        var failures = 0
        for (name, kind, source, expected) in cases {
            do {
                let statements = try SQLScript.statements(source, kind: kind)
                if statements.count == expected { print("PASS \(name)") }
                else { failures += 1; print("FAIL \(name): expected \(expected), got \(statements.count) :: \(statements)") }
            } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        for source in ["SELECT 'unfinished", "SELECT $$unfinished", "SELECT 1 /* unfinished", "SELECT '\0'", "CREATE FUNCTION f() RETURNS int LANGUAGE SQL BEGIN ATOMIC SELECT 1;"] {
            do { _ = try SQLScript.statements(source, kind: .postgresql); failures += 1; print("FAIL unterminated input accepted") }
            catch { print("PASS unterminated input rejected") }
        }
        print("BOUNDARY REVIEW: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
