import Foundation
import JavaScriptCore

/// Runs only in the separate --mongo-shell-worker process. No file or OS APIs are exposed to JS.
final class MongoShellRuntime {
    private var client: UnsafeMutableRawPointer?
    private let context: JSContext
    private let uri: String
    private(set) var database: String

    init(uri: String, database: String, libraryURL: URL) throws {
        self.uri = uri; self.database = database
        guard let context = JSContext() else { throw DatabaseFailure(String(localized: "无法创建 JavaScript 执行环境。", bundle: TableViewerLocalization.bundle)) }
        self.context = context
        var error: UnsafeMutablePointer<CChar>?
        client = tv_mongo_open(uri, &error)
        guard let client else {
            defer { free(error) }
            throw DatabaseFailure(error.map { TableViewerLocalization.bundle.localizedString(forKey: String(cString: $0), value: nil, table: nil) } ?? String(localized: "无法创建 Shell 连接。", bundle: TableViewerLocalization.bundle))
        }
        let command: @convention(block) (String, String) -> String = { db, json in
            var failure: UnsafeMutablePointer<CChar>?
            guard let reply = tv_mongo_command(client, db, json, &failure) else {
                defer { free(failure) }
                let message = (failure.map { TableViewerLocalization.bundle.localizedString(forKey: String(cString: $0), value: nil, table: nil) } ?? String(localized: "MongoDB 命令失败", bundle: TableViewerLocalization.bundle)).replacingOccurrences(of: uri, with: String(localized: "<连接 URI>", bundle: TableViewerLocalization.bundle))
                return (try? jsonText(["__tableviewerError": message])) ?? "{}"
            }
            defer { free(reply) }
            return String(cString: reply)
        }
        let oid: @convention(block) () -> String = { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(24)) }
        context.setObject(command, forKeyedSubscript: "__nativeCommand" as NSString)
        let localize: @convention(block) (String) -> String = { TableViewerLocalization.bundle.localizedString(forKey: $0, value: nil, table: nil) }
        context.setObject(localize, forKeyedSubscript: "__localized" as NSString)
        context.setObject(oid, forKeyedSubscript: "__newOID" as NSString)
        context.evaluateScript(try String(contentsOf: libraryURL, encoding: .utf8))
        if let exception = context.exception { throw DatabaseFailure(exception.toString() ?? String(localized: "Shell 初始化失败", bundle: TableViewerLocalization.bundle)) }
        context.objectForKeyedSubscript("__useDatabase")?.call(withArguments: [database])
        _ = try evaluate("db.runCommand({ping:1})")
    }
    deinit { if let client { tv_mongo_close(client) } }

    func evaluate(_ source: String) throws -> String {
        context.exception = nil
        context.evaluateScript("__printed = []")
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var code = source
        if trimmed.hasPrefix("use ") {
            let name = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw DatabaseFailure(String(localized: "use 后需要数据库名称。", bundle: TableViewerLocalization.bundle)) }
            context.objectForKeyedSubscript("__useDatabase")?.call(withArguments: [name]); database = name
            return "switched to db \(name)"
        }
        switch trimmed {
        case "show dbs", "show databases": code = "db.adminCommand({listDatabases:1,nameOnly:true}).databases"
        case "show collections", "show tables": code = "db.getCollectionNames()"
        case "help", "help()": return Self.help
        case "it": code = "__lastCursor ? __lastCursor : __localized('No cursor to continue.')"
        default: break
        }
        let value = context.evaluateScript(code)
        if let exception = context.exception { throw DatabaseFailure((exception.toString() ?? String(localized: "JavaScript 执行失败", bundle: TableViewerLocalization.bundle)).replacingOccurrences(of: uri, with: String(localized: "<连接 URI>", bundle: TableViewerLocalization.bundle))) }
        let rendered = context.objectForKeyedSubscript("__render")?.call(withArguments: [value ?? JSValue(undefinedIn: context)!])?.toString() ?? ""
        if let exception = context.exception { throw DatabaseFailure(exception.toString() ?? String(localized: "结果显示失败", bundle: TableViewerLocalization.bundle)) }
        database = context.objectForKeyedSubscript("__currentDatabase")?.toString() ?? database
        let safe = rendered.replacingOccurrences(of: uri, with: String(localized: "<连接 URI>", bundle: TableViewerLocalization.bundle))
        return safe.count > 120_000 ? String(safe.prefix(120_000)) + String(localized: "\n…输出已截断，请缩小查询范围。", bundle: TableViewerLocalization.bundle) : safe
    }
    static var help: String { String(localized: """
    TableViewer Mongo Shell · JavaScriptCore + 原生驱动
    show dbs / show collections / use <database> / it / help
    db.collection.find({}).sort({name:1}).limit(20)
    db.collection.findOne({}) / countDocuments({}) / aggregate([...])
    db.collection.insertOne({...}) / insertMany([...])
    db.collection.updateOne({...}, {$set:{...}}) / updateMany(...)
    db.collection.deleteOne({...}) / deleteMany(...) / getIndexes()
    db.runCommand({...}) / db.adminCommand({...})
    rs.status() / rs.conf() / db.hello()
    ObjectId("...") / ISODate("...") / NumberLong("...") / NumberDecimal("...")
    支持 JavaScript 变量、表达式与 print()。不提供 Node.js、文件系统、网络或 npm 模块。
    查询默认最多 1,000 条，每批显示 20 条，输入 it 继续。Ctrl+Enter 运行；运行中的脚本可以停止。
    写入命令直接执行。停止或超时不会撤销已经完成的数据库写入。
    """, bundle: TableViewerLocalization.bundle) }
}

enum MongoShellWorker {
    static func run() {
        var runtime: MongoShellRuntime?
        func reply(_ object: [String: Any]) {
            let text = (try? jsonText(object)) ?? "{\"ok\":false,\"error\":\"Result encoding failed\"}"
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
        }
        while let line = readLine() {
            do {
                let request = try jsonObject(line)
                if request["type"] as? String == "connect" {
                    guard let uri = request["uri"] as? String, let db = request["database"] as? String else { throw DatabaseFailure(String(localized: "缺少连接参数。", bundle: TableViewerLocalization.bundle)) }
                    let library = ProcessInfo.processInfo.environment["TABLEVIEWER_SHELL_LIBRARY"].map { URL(fileURLWithPath: $0) } ?? Bundle.main.url(forResource: "MongoShell", withExtension: "js") ?? Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/MongoShell.js")
                    guard let library else { throw DatabaseFailure(String(localized: "Shell 资源缺失，请重新构建应用。", bundle: TableViewerLocalization.bundle)) }
                    runtime = try MongoShellRuntime(uri: uri, database: db, libraryURL: library)
                    reply(["ok": true, "output": String(localized: "已连接 · 输入 help 查看命令", bundle: TableViewerLocalization.bundle), "database": db])
                } else {
                    guard let runtime else { throw DatabaseFailure(String(localized: "Shell 尚未连接。", bundle: TableViewerLocalization.bundle)) }
                    let output = try runtime.evaluate(request["code"] as? String ?? "")
                    reply(["ok": true, "output": output, "database": runtime.database])
                }
            } catch { reply(["ok": false, "error": error.localizedDescription]) }
        }
    }
}
