import Foundation

@main struct FeatureIntegration {
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        guard condition() else { throw DatabaseFailure("FAIL: " + name) }
        print("PASS: " + name)
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--mongo-shell-worker") { MongoShellWorker.run(); return }
        setbuf(stdout, nil)
        let environment = ProcessInfo.processInfo.environment
        if environment["TABLEVIEWER_SANDBOX_TEST"] == "1" {
            try check(NSHomeDirectory().contains("/Library/Containers/"), "test host runs inside App Sandbox container")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-\(UUID()).sqlite")
            var handle: OpaquePointer?
            sqlite3_open(file.path, &handle); sqlite3_close(handle)
            let sqlite = DatabaseEngine()
            _ = try await sqlite.connect(ConnectionProfile(name: "Sandbox SQLite", path: file.path), secret: "")
            _ = try await sqlite.run("PRAGMA journal_mode = WAL")
            _ = try await sqlite.run("CREATE TABLE sandbox_records(id INTEGER PRIMARY KEY)")
            _ = try await sqlite.run("INSERT INTO sandbox_records VALUES(1)")
            let data = try await sqlite.run("SELECT id FROM sandbox_records")
            try check(data.rows.first?.cells.first == .text("1"), "sandbox SQLite reads and writes container files")
            await sqlite.disconnect()
            var bookmarked = ConnectionProfile(name: "Bookmarked SQLite", path: file.path)
            bookmarked.fileBookmark = try file.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmarked.directoryBookmark = try file.deletingLastPathComponent().bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let restored = try JSONDecoder().decode(ConnectionProfile.self, from: JSONEncoder().encode(bookmarked))
            _ = try await sqlite.connect(restored, secret: "")
            let reopened = try await sqlite.run("SELECT id FROM sandbox_records")
            try check(reopened.rows.first?.cells.first == .text("1"), "persisted file and directory bookmarks reconnect WAL database inside sandbox")
            await sqlite.disconnect(); try FileManager.default.removeItem(at: file)
        }
        let port = environment["TABLEVIEWER_REPLICA_PORT"]!
        let uri = "mongodb://127.0.0.1:\(port)/?directConnection=true"
        let profile = ConnectionProfile(name: "Replica fixture", kind: .mongodb, host: "127.0.0.1", port: port, database: "tableviewer_feature_tests")
        let engine = DatabaseEngine()
        _ = try await engine.connect(profile, secret: uri)
        let replica = try await engine.replicaSetStatus()
        try check(replica.topology == "副本集" && replica.setName == "tvrs" && replica.members.count == 3, "three-member replica set discovery")
        try check(replica.members.filter { $0.role == "PRIMARY" }.count == 1 && replica.members.filter { $0.role == "SECONDARY" }.count == 2, "primary / secondary roles")
        try check(replica.members.allSatisfy { $0.healthy == true } && replica.majority == 2, "replica health and majority")
        try check(replica.members.filter { $0.role == "SECONDARY" }.allSatisfy { $0.lagSeconds != nil }, "replica lag from primary optime")
        let fallback = try ReplicaSnapshot.parse(hello: ["setName":"tvrs", "hosts":["a:27017","b:27017"],"primary":"a:27017"], status: nil, notice: "denied")
        try check(fallback.members.count == 2 && fallback.members.allSatisfy { $0.healthy == nil && $0.lagSeconds == nil }, "unavailable status remains unknown")
        await engine.disconnect()

        let executable = environment["TABLEVIEWER_SANDBOX_TEST"] == "1" ? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TableViewerShell") : URL(fileURLWithPath: CommandLine.arguments[0])
        let shell = ShellSession(executable: executable, timeout: .seconds(12))
        var reply = try await shell.execute("let saved = 41; saved + 1", profile: profile, secret: uri)
        try check(reply.ok && reply.output == "42", "shell evaluates JavaScript in worker")
        reply = try await shell.execute("saved += 1; saved", profile: profile, secret: uri)
        try check(reply.output == "42", "shell persists variables")
        reply = try await shell.execute("db.records.insertMany(Array.from({length:45}, (_,i) => ({n:i, name:'item '+i, big:NumberLong('9223372036854775806')})))", profile: profile, secret: uri)
        try check(reply.ok, "shell inserts BSON documents")
        reply = try await shell.execute("db.records.find({n:{$gte:0}}).sort({n:1})", profile: profile, secret: uri)
        try check(reply.ok && reply.output?.contains(Bundle.main.localizedString(forKey: "\nEnter it to display the next batch.", value: nil, table: nil)) == true && reply.output?.contains("item 19") == true, "shell cursor first batch")
        reply = try await shell.execute("it", profile: profile, secret: uri)
        try check(reply.ok && reply.output?.contains("item 20") == true && reply.output?.contains("item 39") == true, "shell cursor continuation")
        reply = try await shell.execute("db.records.countDocuments({n:{$gte:40}})", profile: profile, secret: uri)
        try check(reply.output?.contains("5") == true, "shell countDocuments")
        reply = try await shell.execute("db.records.updateOne({n:0},{$set:{name:'changed'}}); db.records.findOne({n:0})", profile: profile, secret: uri)
        try check(reply.ok && reply.output?.contains("changed") == true && reply.output?.contains("9223372036854775806") == true, "shell update and Int64 preservation")
        reply = try await shell.execute("rs.status().members.map(m=>m.stateStr)", profile: profile, secret: uri)
        try check(reply.ok && reply.output?.contains("PRIMARY") == true && reply.output?.contains("SECONDARY") == true, "shell rs.status helper")
        reply = try await shell.execute("show collections", profile: profile, secret: uri)
        try check(reply.output?.contains("records") == true, "shell show collections")
        reply = try await shell.execute("use another_database", profile: profile, secret: uri)
        try check(reply.database == "another_database", "shell database switching")
        reply = try await shell.execute("notAFunction()", profile: profile, secret: uri)
        try check(!reply.ok && reply.error?.contains("ReferenceError") == true, "shell JavaScript errors are recoverable")
        let running = Task { try await shell.execute("while(true) {}", profile: profile, secret: uri) }
        try await Task.sleep(for: .milliseconds(300))
        await shell.stop()
        do { _ = try await running.value; throw DatabaseFailure("stop failed") } catch { try check(error.localizedDescription.contains("停止"), "stop terminates infinite JavaScript without blocking app") }
        reply = try await shell.execute("1+2", profile: profile, secret: uri)
        try check(reply.output == "3", "shell reconnects after stop")
        await shell.stop()

        let client = OpenAICompatibleClient()
        var configuration = AgentConfiguration(baseURL: environment["TABLEVIEWER_MOCK_API"]!, model: "stream-tools")
        let context = AgentContext(connectionID: profile.id, connectionName: profile.name, kind: .mongodb, schema: nil)
        let models = try await client.models(configuration: configuration, key: "fixture-key")
        try check(models == ["plain", "stream-tools"], "compatible models endpoint and authorization header")
        let messages = [AgentMessage(role: "user", content: "检查结构")]
        let completion = try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context) { _ in }
        try check(completion.content == "我会先检查结构。" && completion.toolCalls?.count == 1 && completion.toolCalls?.first?.function.name == "inspect_schema", "SSE fragmented tool calls and Chinese text")
        try check(completion.toolCalls?.first?.function.arguments == "{}", "streamed tool arguments assemble without executing")
        configuration.model = "plain"; configuration.streaming = false
        let plain = try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context) { _ in }
        try check(plain.content == "兼容接口连接正常", "non-streaming completion fallback")
        configuration.model = "truncated"; configuration.streaming = true
        do { _ = try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context) { _ in }; throw DatabaseFailure("Expected interrupted stream") }
        catch { try check(error.localizedDescription.contains("提前结束"), "interrupted streams never produce executable actions") }
        configuration.model = "unauthorized"
        do { _ = try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context) { _ in }; throw DatabaseFailure("Expected HTTP error") }
        catch { try check(error.localizedDescription.contains("401") && !error.localizedDescription.contains("fixture-key"), "API errors redact secret") }
        configuration.model = "redirect"
        do { _ = try await client.complete(configuration: configuration, key: "fixture-key", messages: messages, context: context) { _ in }; throw DatabaseFailure("Expected redirect block") }
        catch { try check(error.localizedDescription.contains("重定向"), "API redirects do not forward credentials") }
        configuration.baseURL = "https://example.com/v1/chat/completions"
        let modelsURL = try configuration.endpoint("models")
        try check(modelsURL.absoluteString == "https://example.com/v1/models", "base URL normalization")
        configuration.baseURL = "https://user:password@example.com/v1"
        do { _ = try configuration.endpoint("models"); throw DatabaseFailure("Expected URL rejection") }
        catch { try check(error.localizedDescription.contains("凭据"), "credentials excluded from base URL") }
        print("ALL V0.2 FEATURE CHECKS PASSED")
    }
}
