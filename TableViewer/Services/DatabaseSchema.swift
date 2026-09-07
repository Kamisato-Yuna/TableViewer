import Foundation

extension DatabaseEngine {
    /// Catalog reads only; no user table scan is needed for SQL schema inspection.
    func schemaMetadata(for object: DatabaseObject) throws -> SchemaMetadata {
        guard let profile else { throw DatabaseFailure("未连接。") }
        switch profile.kind {
        case .sqlite: return try sqliteSchema(object)
        case .postgresql: return try postgresSchema(object)
        case .mongodb:
            let response = try mongoCommand(["listCollections": 1, "filter": ["name": object.name], "cursor": ["batchSize": 1]])
            let collection = ((response["cursor"] as? [String: Any])?["firstBatch"] as? [[String: Any]])?.first ?? [:]
            let indexes: [String: Any] = object.isView ? [:] : try mongoCommand(["listIndexes": object.name, "cursor": ["batchSize": 1000]], name: "listIndexes")
            let documents = (indexes["cursor"] as? [String: Any])?["firstBatch"] as? [[String: Any]] ?? []
            let fields = (((collection["options"] as? [String: Any])?["validator"] as? [String: Any])?["$jsonSchema"] as? [String: Any]) ?? [:]
            let required = fields["required"] as? [String] ?? []
            let properties = fields["properties"] as? [String: [String: Any]] ?? [:]
            return SchemaMetadata(fields: try properties.keys.sorted().map { name in
                SchemaField(name: name, type: try jsonText(properties[name]?["bsonType"] ?? String(localized: "未声明")), constraints: required.contains(name) ? ["REQUIRED"] : [])
            }, indexes: try documents.map { SchemaIndex(name: $0["name"] as? String ?? "", definition: try jsonText($0, pretty: true), unique: $0["unique"] as? Bool ?? false) }, ddl: try jsonText(collection, pretty: true), notice: String(localized: "MongoDB 没有声明式外键；此处展示集合定义、验证器声明字段和索引，不推断文档间关联。定义导出为 JSON。"))
        }
    }

    func relationships(for objects: [DatabaseObject]) throws -> [TableRelationship] {
        guard profile?.kind != .mongodb else { return [] }
        return try objects.filter { !$0.isView }.flatMap { object in
            if profile?.kind == .sqlite { return try sqliteRelationships(object) }
            return try postgresRelationships(object)
        }
    }

    private func sqliteRelationships(_ object: DatabaseObject) throws -> [TableRelationship] {
        let rows = try catalogSQL("SELECT * FROM pragma_foreign_key_list(?) ORDER BY id,seq", parameters: [.text(object.name)]).rows
        let groups = Dictionary(grouping: rows, by: { $0.cells[0].display })
        return try groups.keys.sorted().compactMap { key in
            let rows = groups[key]!.sorted { (Int($0.cells[1].display) ?? 0) < (Int($1.cells[1].display) ?? 0) }
            guard let first = rows.first else { return nil }
            let primary = try catalogSQL("SELECT * FROM pragma_table_xinfo(?) ORDER BY cid", parameters: [.text(first.cells[2].display)]).rows.filter { (Int($0.cells[5].display) ?? 0) > 0 }.sorted { (Int($0.cells[5].display) ?? 0) < (Int($1.cells[5].display) ?? 0) }
            let targets = rows.enumerated().map { index, row in row.cells[4].string ?? (index < primary.count ? primary[index].cells[1].display : "PRIMARY KEY") }
            return TableRelationship(name: "fk_" + key, source: object, target: DatabaseObject(name: first.cells[2].display), sourceColumns: rows.map { $0.cells[3].display }, targetColumns: targets)
        }
    }

    private func sqliteSchema(_ object: DatabaseObject) throws -> SchemaMetadata {
        let rows = try catalogSQL("SELECT * FROM pragma_table_xinfo(?) ORDER BY cid", parameters: [.text(object.name)]).rows
        let relationships = try sqliteRelationships(object)
        var indexes: [SchemaIndex] = []
        var uniqueFields = Set<String>()
        for row in try catalogSQL("SELECT * FROM pragma_index_list(?) ORDER BY seq", parameters: [.text(object.name)]).rows {
            let name = row.cells[1].display
            let parts = try catalogSQL("SELECT * FROM pragma_index_info(?) ORDER BY seqno", parameters: [.text(name)]).rows
            let unique = row.cells[2].display == "1"
            // Composite uniqueness does not make each constituent field unique.
            if unique && row.cells.count > 4 && row.cells[4].display == "0" && parts.count == 1, let field = parts.first?.cells[2].string { uniqueFields.insert(field) }
            let ddl = try catalogSQL("SELECT sql FROM sqlite_schema WHERE type='index' AND name=?", parameters: [.text(name)]).rows.first?.cells[0].string
            indexes.append(SchemaIndex(name: name, definition: ddl ?? String(localized: "自动索引") + " (" + parts.map { $0.cells[2].string ?? String(localized: "表达式") }.joined(separator: ", ") + ")", unique: unique))
        }
        let ddl = try catalogSQL("SELECT sql FROM sqlite_schema WHERE name=? AND type IN ('table','view')", parameters: [.text(object.name)]).rows.first?.cells[0].string ?? ""
        return SchemaMetadata(fields: rows.map { row in
            let name = row.cells[1].display
            var constraints: [String] = []
            if row.cells[3].display == "1" { constraints.append("NOT NULL") }
            if (Int(row.cells[5].display) ?? 0) > 0 { constraints.append("PRIMARY KEY") }
            if uniqueFields.contains(name) { constraints.append("UNIQUE") }
            if relationships.contains(where: { $0.sourceColumns.contains(name) }) { constraints.append("FOREIGN KEY") }
            if row.cells.count > 6 && row.cells[6].display != "0" { constraints.append("GENERATED") }
            return SchemaField(name: name, type: row.cells[2].display, constraints: constraints, defaultValue: row.cells[4].string)
        }, indexes: indexes, relationships: relationships, ddl: ([ddl] + indexes.filter { !$0.definition.hasPrefix(String(localized: "自动索引")) }.map(\.definition)).filter { !$0.isEmpty }.map { $0 + ";" }.joined(separator: "\n\n"), notice: String(localized: "SQLite 原始建表/视图定义包含 CHECK、复合约束及生成列表达式；筛选标签仅标记已读取的字段约束。"))
    }

    private func postgresRelationships(_ object: DatabaseObject) throws -> [TableRelationship] {
        let rows = try catalogSQL("""
        SELECT c.conname, tn.nspname, t.relname, sa.attname, ta.attname
        FROM pg_constraint c JOIN pg_class s ON s.oid=c.conrelid JOIN pg_namespace sn ON sn.oid=s.relnamespace
        JOIN pg_class t ON t.oid=c.confrelid JOIN pg_namespace tn ON tn.oid=t.relnamespace
        CROSS JOIN LATERAL unnest(c.conkey,c.confkey) WITH ORDINALITY AS k(src,dst,ord)
        JOIN pg_attribute sa ON sa.attrelid=s.oid AND sa.attnum=k.src
        JOIN pg_attribute ta ON ta.attrelid=t.oid AND ta.attnum=k.dst
        WHERE c.contype='f' AND sn.nspname=$1 AND s.relname=$2 ORDER BY c.conname,k.ord
        """, parameters: [.text(object.schema), .text(object.name)]).rows
        let groups = Dictionary(grouping: rows, by: { $0.cells[0].display })
        return groups.keys.sorted().map { name in
            let rows = groups[name]!
            return TableRelationship(name: name, source: object, target: DatabaseObject(name: rows[0].cells[2].display, schema: rows[0].cells[1].display), sourceColumns: rows.map { $0.cells[3].display }, targetColumns: rows.map { $0.cells[4].display })
        }
    }

    private func postgresSchema(_ object: DatabaseObject) throws -> SchemaMetadata {
        let parameters: [CellValue] = [.text(object.schema), .text(object.name)]
        let rows = try catalogSQL("""
        SELECT a.attname, format_type(a.atttypid,a.atttypmod), a.attnotnull::text,
          pg_get_expr(d.adbin,d.adrelid), a.attidentity::text, a.attgenerated::text,
          COALESCE((SELECT string_agg(c.contype::text,',') FROM pg_constraint c WHERE c.conrelid=t.oid AND a.attnum=ANY(c.conkey)), '')
        FROM pg_attribute a JOIN pg_class t ON t.oid=a.attrelid JOIN pg_namespace n ON n.oid=t.relnamespace
        LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
        WHERE n.nspname=$1 AND t.relname=$2 AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum
        """, parameters: parameters).rows
        let fields = rows.map { row in
            var constraints: [String] = row.cells[2].display == "true" ? ["NOT NULL"] : []
            for code in row.cells[6].display.split(separator: ",") {
                if let label = ["p": "PRIMARY KEY", "u": "UNIQUE MEMBER", "f": "FOREIGN KEY", "c": "CHECK"][String(code)] { constraints.append(label) }
            }
            if !row.cells[4].display.isEmpty { constraints.append("IDENTITY") }
            if !row.cells[5].display.isEmpty { constraints.append("GENERATED") }
            return SchemaField(name: row.cells[0].display, type: row.cells[1].display, constraints: constraints, defaultValue: row.cells[3].string)
        }
        let indexes = try catalogSQL("SELECT indexname,indexdef FROM pg_indexes WHERE schemaname=$1 AND tablename=$2 ORDER BY indexname", parameters: parameters).rows.map { SchemaIndex(name: $0.cells[0].display, definition: $0.cells[1].display, unique: $0.cells[1].display.contains("CREATE UNIQUE INDEX")) }
        let constraints = try catalogSQL("SELECT c.conname,pg_get_constraintdef(c.oid,true) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname=$1 AND t.relname=$2 ORDER BY c.conname", parameters: parameters).rows
        let ddl: String
        if object.isView {
            let definition = try catalogSQL("SELECT pg_get_viewdef(c.oid,true) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=$1 AND c.relname=$2", parameters: parameters).rows.first?.cells[0].display ?? ""
            ddl = "CREATE VIEW \(object.qualifiedName) AS\n\(definition)"
        } else {
            let definitions = rows.map { row -> String in
                var text = quoteIdentifier(row.cells[0].display) + " " + row.cells[1].display
                if !row.cells[5].display.isEmpty { text += " GENERATED ALWAYS AS (\(row.cells[3].string ?? "")) STORED" }
                else if !row.cells[4].display.isEmpty { text += row.cells[4].display == "a" ? " GENERATED ALWAYS AS IDENTITY" : " GENERATED BY DEFAULT AS IDENTITY" }
                else if let value = row.cells[3].string { text += " DEFAULT " + value }
                if row.cells[2].display == "true" { text += " NOT NULL" }
                return text
            } + constraints.map { "CONSTRAINT " + quoteIdentifier($0.cells[0].display) + " " + $0.cells[1].display }
            ddl = "-- " + String(localized: "结构参考 DDL；不包含所有权、权限、分区、序列参数及存储选项。完整迁移请使用 pg_dump。") + "\nCREATE TABLE \(object.qualifiedName) (\n  " + definitions.joined(separator: ",\n  ") + "\n);\n\n-- " + String(localized: "索引定义（约束自动创建的索引请勿重复执行）") + "\n" + indexes.map { $0.definition + ";" }.joined(separator: "\n")
        }
        return SchemaMetadata(fields: fields, indexes: indexes, relationships: try postgresRelationships(object), ddl: ddl, notice: String(localized: "PostgreSQL 目录元数据；UNIQUE MEMBER 表示参与唯一约束，复合约束不保证单列唯一。DDL 为结构参考，完整迁移请使用 pg_dump。"))
    }
}
