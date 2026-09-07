import Foundation

/// Lexical boundaries only. Execution still uses each engine's native parser.
enum SQLScript {
    static func statements(_ source: String, kind: DatabaseKind, standardConformingStrings: Bool = true) throws -> [String] {
        if kind == .mongodb { return [source] }
        guard !source.contains("\0") else { throw DatabaseFailure(String(localized: "SQL 语句不能包含 NUL 字符。")) }
        if kind == .sqlite {
            // sqlite3_complete understands trigger bodies, quoted semicolons and comments.
            var parts: [String] = [], buffer = ""
            for character in source {
                buffer.append(character)
                if character == ";", sqlite3_complete(buffer) != 0 {
                    if !tokens(buffer, kind: .sqlite).isEmpty { parts.append(buffer) }; buffer = ""
                }
            }
            if !tokens(buffer, kind: .sqlite).isEmpty { parts.append(buffer) }
            return parts
        }
        return try scan(source, split: true, standardConformingStrings: standardConformingStrings).statements
    }

    /// Removes comments and quoted content for conservative UI classification, never authorization.
    static func tokens(_ sql: String, kind: DatabaseKind = .postgresql, standardConformingStrings: Bool = true) -> [String] {
        (try? scan(sql, split: false, nestedComments: kind != .sqlite, standardConformingStrings: standardConformingStrings).words) ?? []
    }

    /// PostgreSQL session settings can change after each command (including function
    /// calls). The executor reads PQparameterStatus before taking the next boundary.
    /// Content after the first complete statement is intentionally not parsed yet.
    static func nextPostgreSQLStatement(_ source: String, standardConformingStrings: Bool) throws -> (statement: String, remainder: String)? {
        guard !source.contains("\0") else { throw DatabaseFailure(String(localized: "SQL 语句不能包含 NUL 字符。")) }
        let scanned = try scan(source, split: true, standardConformingStrings: standardConformingStrings, firstOnly: true)
        guard let statement = scanned.statements.first else { return nil }
        return (statement, String(source.dropFirst(scanned.consumed)))
    }

    private static func scan(_ source: String, split: Bool, nestedComments: Bool = true, standardConformingStrings: Bool = true, firstOnly: Bool = false) throws -> (statements: [String], words: [String], consumed: Int) {
        let chars = Array(source)
        var i = 0, start = 0, commentDepth = 0
        var quote: Character?, dollar: [Character]?, lineComment = false, escaped = false
        var parts: [String] = [], words: [String] = [], statementHasContent = false
        // Only SQL-standard BEGIN ATOMIC bodies suppress statement delimiters. CASE
        // expressions nest inside a body and their END must not close that body.
        enum Body { case atomic, caseExpression }
        var bodies: [Body] = []
        var previousWord: String?
        func identifierStart(_ c: Character) -> Bool {
            c == "_" || c.isLetter || c.unicodeScalars.contains { $0.value >= 128 }
        }
        func identifierPart(_ c: Character) -> Bool { identifierStart(c) || c.isNumber || c == "$" }
        func finish(_ end: Int) {
            if statementHasContent { parts.append(String(chars[start..<end])) }
            start = end; statementHasContent = false; previousWord = nil
        }
        while i < chars.count {
            let c = chars[i], next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if lineComment {
                // Swift treats CRLF as one extended grapheme cluster.
                if c == "\n" || c == "\r" || c == "\r\n" { lineComment = false }
                i += 1; continue
            }
            if commentDepth > 0 {
                if nestedComments && c == "/" && next == "*" { commentDepth += 1; i += 2 }
                else if c == "*" && next == "/" { commentDepth -= 1; i += 2 }
                else { i += 1 }
                continue
            }
            if let marker = dollar {
                let end = i + marker.count
                if end <= chars.count && Array(chars[i..<end]) == marker { dollar = nil; i = end }
                else { i += 1 }
                continue
            }
            if let q = quote {
                if escaped && c == "\\" { i += min(2, chars.count - i); continue }
                if c == q { if next == q { i += 2; continue }; quote = nil }
                i += 1; continue
            }
            if c == "-" && next == "-" { lineComment = true; i += 2; continue }
            if c == "/" && next == "*" { commentDepth = 1; i += 2; continue }
            if c == "'" || c == "\"" {
                quote = c
                escaped = c == "'" && (!standardConformingStrings || (i > 0 && (chars[i - 1] == "E" || chars[i - 1] == "e") && (i < 2 || !identifierPart(chars[i - 2]))))
                statementHasContent = true; previousWord = nil; i += 1; continue
            }
            if c == "$", i == 0 || !identifierPart(chars[i - 1]) {
                var j = i + 1
                if j < chars.count, identifierStart(chars[j]) {
                    j += 1
                    while j < chars.count && (identifierStart(chars[j]) || chars[j].isNumber) { j += 1 }
                }
                if j < chars.count && chars[j] == "$" {
                    dollar = Array(chars[i...j]); statementHasContent = true; previousWord = nil; i = j + 1; continue
                }
            }
            if identifierStart(c) {
                var end = i + 1
                while end < chars.count && identifierPart(chars[end]) { end += 1 }
                let word = String(chars[i..<end]).uppercased()
                words.append(word); statementHasContent = true
                if split {
                    if word == "ATOMIC" && previousWord == "BEGIN" { bodies.append(.atomic) }
                    else if word == "CASE" && !bodies.isEmpty { bodies.append(.caseExpression) }
                    else if word == "END" && !bodies.isEmpty { bodies.removeLast() }
                }
                previousWord = word; i = end; continue
            }
            if c == ";" {
                if split && bodies.isEmpty {
                    finish(i + 1)
                    if firstOnly && !parts.isEmpty { return (parts, words, i + 1) }
                }
                previousWord = nil
            } else if !c.isWhitespace {
                statementHasContent = true; previousWord = nil
            }
            i += 1
        }
        if split {
            guard quote == nil, dollar == nil, commentDepth == 0, bodies.isEmpty else { throw DatabaseFailure(String(localized: "SQL 引号、注释或 BEGIN ATOMIC 块未闭合。")) }
        }
        finish(chars.count)
        return (parts, words, chars.count)
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
