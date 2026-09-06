import Foundation

/// 真实 OrbStack 数据库 + 应用实际驱动；每个场景独立记录，不将断言数当作覆盖率。
@main struct OrbStackE2E {
    static var results: [[String: Any]] = []
    static let env = ProcessInfo.processInfo.environment
    static let names = ["customers", "orders", "products", "payments", "shipments", "inventory", "events", "tickets", "reviews", "sessions"]
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw DatabaseFailure(message) }
    }
    static func scenario(_ id: String, _ body: () async throws -> Void) async {
        let start = Date()
        do {
            try await body()
            results.append(["id": id, "status": "passed", "seconds": Date().timeIntervalSince(start)])
            print("PASS \(id)")
        } catch {
            results.append(["id": id, "status": "failed", "error": error.localizedDescription, "seconds": Date().timeIntervalSince(start)])
            print("FAIL \(id): \(error.localizedDescription)")
        }
    }
    static func rejects(_ body: () async throws -> Void) async throws {
        var rejected = false
        do { try await body() } catch { rejected = true }
        try check(rejected, "应拒绝操作但实际成功")
    }
    static func cell(_ r: QueryResult, _ row: Int, _ name: String) throws -> CellValue {
        guard r.rows.indices.contains(row), let i = r.columns.firstIndex(where: { $0.name == name }), r.rows[row].cells.indices.contains(i) else { throw DatabaseFailure("结果缺少 \(name) / row \(row)") }
        return r.rows[row].cells[i]
    }
    static func main() async throws {
        setbuf(stdout, nil)
        for kind in [DatabaseKind.postgresql, .mongodb] { await database(kind) }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: env["TABLEVIEWER_E2E_RESULTS"]!))
        if results.contains(where: { $0["status"] as? String != "passed" }) { exit(1) }
    }
    static func database(_ kind: DatabaseKind) async {
        let isPG = kind == .postgresql
        let prefix = isPG ? "PG" : "MG"
        let engine = DatabaseEngine()
        let profile = ConnectionProfile(name: "OrbStack E2E", kind: kind, host: "127.0.0.1", port: env[isPG ? "TABLEVIEWER_TEST_PG_PORT" : "TABLEVIEWER_TEST_MONGO_PORT"]!, database: "tableviewer_test", user: "postgres", sslMode: "disable")
        let secret = isPG ? env["TABLEVIEWER_TEST_PG_PASSWORD"]! : "mongodb://tableviewer:\(env["TABLEVIEWER_TEST_MONGO_PASSWORD"]!)@127.0.0.1:\(profile.port)/?authSource=admin"
        let objects = names.map { DatabaseObject(name: $0, schema: isPG ? "public" : "") }
        let object = objects[0]
        func query(_ sql: String, _ json: String) async throws -> QueryResult { try await engine.run(isPG ? sql : json) }
        await scenario(prefix + "01") { _ = try await engine.connect(profile, secret: secret) }
        await scenario(prefix + "02") {
            let wrong = isPG ? "incorrect-e2e-password" : "mongodb://tableviewer:incorrect-e2e-password@127.0.0.1:\(profile.port)/?authSource=admin"
            try await rejects { _ = try await engine.connect(profile, secret: wrong) }
            _ = try await engine.connect(profile, secret: secret)
        }
        await scenario(prefix + "03") {
            let found = try await engine.objects()
            try check(Set(found.map(\.name)) == Set(names), "目录必须恰好包含 10 个业务表/集合")
        }
        await scenario(prefix + "04") {
            for o in objects {
                let r = try await query("SELECT count(*) AS n FROM \(o.qualifiedName)", "{\"count\":\"\(o.name)\"}")
                let n = isPG ? Int(r.rows.first?.cells.first?.display ?? "") ?? -1 : numericValue(try jsonObject(r.rows[0].cells[0].display)["n"])
                try check(n == 50000, "\(o.name) 必须包含 50,000 行")
            }
        }
        await scenario(prefix + "05") {
            let r = try await engine.browse(object)
            try check(r.columns.contains(where: { $0.name == (isPG ? "id" : "_id") && $0.isPrimaryKey }), "主键元数据")
            if isPG {
                try check(r.columns.contains(where: { $0.name == "metadata" && $0.type == "jsonb" }), "JSONB 元数据")
            } else {
                let d = try jsonObject(r.rows[0].document!)
                try check((d["external_id"] as? [String: String])?["$numberLong"] == "9007199254740992" && d["created_at"] != nil && (d["amount"] as? [String: String])?["$numberDecimal"] != nil && d["payload"] != nil, "BSON int64/decimal/date/binary 保真")
            }
        }
        for (id, page, first, last, more) in [("06",0,1,200,true),("07",124,24801,25000,true),("08",249,49801,50000,false)] {
            await scenario(prefix + id) {
                for o in objects {
                    let r = try await engine.browse(o, page: page)
                    try check(r.rows.count == 200 && r.hasMore == more, "\(o.name) 页大小/末页标记")
                    try check(try cell(r,0,"id") == .text(String(first)) && cell(r,199,"id") == .text(String(last)), "\(o.name) 分页边界")
                }
            }
        }
        await scenario(prefix + "09") {
            let r = try await engine.browse(object, page: 250)
            try check(r.rows.isEmpty && !r.hasMore, "越界页必须为空")
        }
        await scenario(prefix + "10") {
            let r = try await engine.browse(object, sort: "id", ascending: false)
            try check(try cell(r,0,"id") == .text("50000") && cell(r,199,"id") == .text("49801"), "降序排序")
        }
        await scenario(prefix + "11") {
            let r = try await query("SELECT * FROM customers WHERE id=43210", "{\"find\":\"customers\",\"filter\":{\"id\":43210}}")
            try check(r.rows.count == 1 && (try cell(r,0,"name")) == .text("customers-模拟-43210"), "精确查询")
        }
        await scenario(prefix + "12") {
            let r = try await query("SELECT count(*) AS n, sum(id) AS total FROM customers", "{\"aggregate\":\"customers\",\"pipeline\":[{\"$group\":{\"_id\":null,\"n\":{\"$sum\":1},\"total\":{\"$sum\":\"$id\"}}}],\"cursor\":{}}")
            try check(try cell(r,0,"n") == .text("50000") && cell(r,0,"total") == .text("1250025000"), "全量聚合")
        }
        await scenario(prefix + "13") {
            let r = try await query("SELECT * FROM customers ORDER BY id", "{\"find\":\"customers\",\"filter\":{},\"batchSize\":1000}")
            try check(r.rows.count == 1000 && r.hasMore, "查询显示有界并提示更多")
        }
        await scenario(prefix + "14") {
            let r = try await engine.browse(object)
            try check(try cell(r,0,"note") == .text("") && cell(r,1,"note") == .text("O'Reilly · 测试 ✓") && cell(r,2,"note") == .null, "空串、Unicode、NULL 必须区分")
        }
        let inserted = isPG ? nil : "{\"_id\":50001,\"id\":50001,\"name\":\"新增 O'Reilly ✓\",\"status\":\"test\",\"external_id\":{\"$numberLong\":\"9223372036854775806\"}}"
        await scenario(prefix + "15") {
            try await engine.insert(object, fields: [("id",.text("50001")),("name",.text("新增 O'Reilly ✓")),("status",.text("test"))], document: inserted)
            let r = try await engine.browse(object, page:250)
            try check(r.rows.count == 1 && (try cell(r,0,"name")) == .text("新增 O'Reilly ✓"), "插入后读取")
        }
        var original: QueryResult?
        await scenario(prefix + "16") {
            let r = try await engine.browse(object, page:250)
            try check(r.rows.count == 1, "编辑测试行存在")
            original = r
            var values = r.rows[0].cells
            values[r.columns.firstIndex(where: { $0.name == "name" })!] = .text("已修改 ✓")
            var document: String?
            if !isPG { var d = try jsonObject(r.rows[0].document!); d["name"] = "已修改 ✓"; document = try jsonText(d) }
            try await engine.update(object, columns:r.columns, original:r.rows[0], values:values, document:document)
            let after = try await engine.browse(object, page:250)
            try check(try cell(after,0,"name") == .text("已修改 ✓"), "编辑后读取")
            if !isPG { try check(try cell(after,0,"external_id") == .text("9223372036854775806"), "编辑不损失 int64") }
        }
        await scenario(prefix + "17") {
            guard let r = original else { throw DatabaseFailure("缺少编辑前记录") }
            var values = r.rows[0].cells
            values[r.columns.firstIndex(where: { $0.name == "name" })!] = .text("过期修改")
            var document: String?
            if !isPG { var d = try jsonObject(r.rows[0].document!); d["name"] = "过期修改"; document = try jsonText(d) }
            try await rejects { try await engine.update(object, columns:r.columns, original:r.rows[0], values:values, document:document) }
            let after = try await engine.browse(object,page:250)
            try check(try cell(after,0,"name") == .text("已修改 ✓"), "冲突未覆盖已保存值")
        }
        await scenario(prefix + "18") {
            try await rejects { try await engine.insert(object, fields:[("id",.text("50001")),("name",.text("duplicate")),("status",.text("test"))], document:inserted) }
            let r = try await engine.browse(object,page:250)
            try check(r.rows.count == 1, "重复主键不新增数据")
        }
        await scenario(prefix + "19") {
            let r = try await engine.browse(object,page:250)
            try check(r.rows.count == 1, "删除前测试行存在")
            try await engine.delete(object,columns:r.columns,row:r.rows[0])
            let after = try await engine.browse(object,page:250)
            try check(after.rows.isEmpty, "仅删除新增测试行")
        }
        await scenario(prefix + "20") {
            try await rejects { _ = try await query("SELECT definitely_missing_column FROM customers", "{\"definitelyMissingCommand\":1}") }
            let r = try await engine.browse(object)
            try check(r.rows.count == 200, "命令失败后仍可浏览")
            await engine.disconnect()
            try await rejects { _ = try await engine.objects() }
            let found = try await engine.connect(profile, secret:secret)
            try check(found.count == 10, "断开后重新连接")
        }
        await engine.disconnect()
    }
}
