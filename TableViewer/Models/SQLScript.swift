import Foundation

/// Lexical boundaries only. Execution still uses each engine's native parser.
enum SQLScript {
    static func statements(_ source: String, kind: DatabaseKind) throws -> [String] {
        if kind == .mongodb { return [source] }
        guard !source.contains("\0") else { throw DatabaseFailure("SQL 语句不能包含 NUL 字符。") }
        if kind == .sqlite {
            // sqlite3_complete understands trigger bodies, quoted semicolons and comments.
            var parts: [String] = [], buffer = ""
            for character in source {
                buffer.append(character)
                if character == ";", sqlite3_complete(buffer) != 0 {
                    if !tokens(buffer).isEmpty { parts.append(buffer) }; buffer = ""
                }
            }
            if !tokens(buffer).isEmpty { parts.append(buffer) }
            return parts
        }
        let chars = Array(source); var i = 0, start = 0, depth = 0
        var quote: Character?, dollar: String?, line = false, escaped = false
        var parts: [String] = []
        while i < chars.count {
            let c = chars[i], next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if line { if c == "\n" { line = false }; i += 1; continue }
            if depth > 0 {
                if c == "/" && next == "*" { depth += 1; i += 2 }
                else if c == "*" && next == "/" { depth -= 1; i += 2 }
                else { i += 1 }; continue
            }
            if let marker = dollar {
                let end = i + marker.count
                if end <= chars.count && String(chars[i..<end]) == marker { dollar = nil; i = end } else { i += 1 }; continue
            }
            if let q = quote {
                if escaped && c == "\\" { i += min(2, chars.count - i); continue }
                if c == q { if next == q { i += 2; continue }; quote = nil }
                i += 1; continue
            }
            if c == "-" && next == "-" { line = true; i += 2; continue }
            if c == "/" && next == "*" { depth = 1; i += 2; continue }
            if c == "'" || c == "\"" {
                quote = c; escaped = c == "'" && i > 0 && (chars[i-1] == "E" || chars[i-1] == "e") && (i < 2 || !(chars[i-2].isLetter || chars[i-2].isNumber || chars[i-2] == "_"))
                i += 1; continue
            }
            if c == "$", i == 0 || !(chars[i-1].isLetter || chars[i-1].isNumber || chars[i-1] == "_" || chars[i-1] == "$") {
                var j = i + 1
                while j < chars.count && (chars[j].isLetter || chars[j].isNumber || chars[j] == "_") { j += 1 }
                if j < chars.count && chars[j] == "$" && (j == i + 1 || !chars[i+1].isNumber) { dollar = String(chars[i...j]); i = j + 1; continue }
            }
            if c == ";" { let part = String(chars[start...i]); if !tokens(part).isEmpty { parts.append(part) }; start = i + 1 }
            i += 1
        }
        guard quote == nil, dollar == nil, depth == 0 else { throw DatabaseFailure("SQL 引号或注释未闭合。") }
        if start < chars.count { let part = String(chars[start...]); if !tokens(part).isEmpty { parts.append(part) } }
        return parts
    }

    /// Removes comments and quoted content for conservative UI classification, never authorization.
    static func tokens(_ sql: String) -> [String] {
        let pattern = #"(?s)/\*.*?\*/|--[^\n]*|'(?:''|[^'])*'|"(?:""|[^"])*"|\b[A-Za-z_][A-Za-z_0-9]*\b"#
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: sql, range: NSRange(sql.startIndex..., in: sql)).compactMap {
            let text = (sql as NSString).substring(with: $0.range)
            return text.first?.isLetter == true ? text.uppercased() : nil
        }
    }
}

struct StatementResult: Identifiable, Sendable {
    let id = UUID()
    var statement: String
    var result: QueryResult?
    var failure: String?
}

struct QueryEstimate: Sendable {
    enum Severity: Int, Sendable { case normal, unknown, large, excessive }
    var severity: Severity
    var summary: String
    var details: String = ""
    var rows: Double?
}
