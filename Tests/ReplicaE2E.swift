import Foundation

@main struct ReplicaE2E {
    struct Configuration: Decodable { let set: String; let database: String; let password: String; let hosts: [String]; let nodes: [String] }
    static let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TABLEVIEWER_REPLICA_OUTPUT"]!)
    static var records: [[String: Any]] = []
    static var snapshots: [[String: Any]] = []
    static func check(_ ok: Bool, _ message: String) throws { if !ok { throw DatabaseFailure(message) } }
    static func scenario(_ id: Int, _ name: String, _ body: () async throws -> Void) async throws {
        let start = Date()
        do {
            try await body()
            records.append(["id":id,"name":name,"status":"passed","seconds":Date().timeIntervalSince(start)])
            print("PASS RS\(String(format:"%02d",id)) \(name)")
        } catch {
            records.append(["id":id,"name":name,"status":"failed","error":error.localizedDescription])
            print("FAIL RS\(id) \(name): \(error.localizedDescription)")
            throw error
        }
    }
    static func poll(_ body: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(90)
        var last = "条件未满足"
        while Date() < deadline {
            do { if try await body() { return } } catch { last = error.localizedDescription }
            try await Task.sleep(for:.seconds(1))
        }
        throw DatabaseFailure("90 秒内未恢复：" + last)
    }
    static func docker(_ verb: String, _ node: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
        process.arguments = ["docker","--context","orbstack",verb,node]
        process.standardOutput = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0,"docker \(verb) \(node) 失败")
    }
    static func response(_ engine: DatabaseEngine, _ text: String) async throws -> [String:Any] {
        let r = try await engine.run(text)
        guard let cell = r.rows.first?.cells.first else { throw DatabaseFailure("缺少命令响应") }
        return try jsonObject(cell.display)
    }
    static func count(_ engine: DatabaseEngine, _ collection: String, id: String? = nil) async throws -> Int {
        let filter = id.map { ",\"query\":{\"_id\":\"\($0)\"}" } ?? ""
        return numericValue(try await response(engine,"{\"count\":\"\(collection)\"\(filter)}")["n"])
    }
    static func write(_ engine: DatabaseEngine, _ command: String) async throws {
        let r = try await response(engine,command)
        try check(bsonNumber(r["ok"]) == 1 && r["writeErrors"] == nil && r["writeConcernError"] == nil,"写入未获得确认：\(try jsonText(r))")
    }
    static func mark(_ engine: DatabaseEngine, _ id: String) async throws {
        try await write(engine,"{\"insert\":\"replica_receipts\",\"documents\":[{\"_id\":\"\(id)\",\"value\":1}],\"writeConcern\":{\"w\":\"majority\",\"wtimeout\":5000}}")
    }
    static func capture(_ engine: DatabaseEngine, _ label: String) async throws -> ReplicaSnapshot {
        let snap = try await engine.replicaSetStatus()
        snapshots.append(["phase":label,"raw":try jsonObject(snap.rawJSON)])
        return snap
    }
    static func main() async throws {
        if CommandLine.arguments.contains("--mongo-shell-worker") { MongoShellWorker.run(); return }
        setbuf(stdout,nil)
        let c = try JSONDecoder().decode(Configuration.self,from:Data(contentsOf:out.appendingPathComponent("connections.json")))
        let uri = "mongodb://tableviewer:\(c.password)@\(c.hosts.joined(separator:","))/?replicaSet=\(c.set)&authSource=admin&retryWrites=true"
        let profile = ConnectionProfile(name:"Replica E2E",kind:.mongodb,database:c.database)
        let engine = DatabaseEngine(), admin = DatabaseEngine()
        var direct: [DatabaseEngine] = []
        let runID = UUID().uuidString
        var stopped: Set<String> = []
        var failure: Error?
        let shell = ShellSession(executable:URL(fileURLWithPath:CommandLine.arguments[0]))
        do {
            try await scenario(1,"三种子 URI 自动发现（非 directConnection）") {
                let found = try await engine.connect(profile,secret:uri)
                try check(found.count >= 10,"未发现业务集合")
                var p=profile; p.database="admin"
                _ = try await admin.connect(p,secret:uri)
            }
            try await scenario(2,"副本集名称、1 主 2 从、健康、多数派 2") {
                let s=try await capture(engine,"initial")
                try check(s.setName==c.set && s.members.count==3 && s.majority==2 && s.members.allSatisfy{$0.healthy==true},"副本集拓扑不完整")
                try check(s.members.filter{$0.role=="PRIMARY"}.count==1 && s.members.filter{$0.role=="SECONDARY"}.count==2,"角色不正确")
                try check(s.members.filter{$0.role=="SECONDARY"}.allSatisfy{$0.lagSeconds != nil},"从节点复制延迟未提供")
                let noOptime: [String:Any] = ["name":"offline", "stateStr":"SECONDARY", "health":0, "optimeDate":["$date":["$numberLong":"0"]]]
                let validPrimary: [String:Any] = ["name":"primary", "stateStr":"PRIMARY", "health":1, "optimeDate":["$date":["$numberLong":"1700000000000"]]]
                let offline = try ReplicaSnapshot.parse(hello:["setName":c.set],status:["members":[validPrimary,noOptime]])
                try check(offline.members.first{$0.name=="offline"}?.lagSeconds==nil,"离线零 optime 不能换算成从 1970 年开始的延迟")
                var initializing = noOptime; initializing["health"] = 1
                let initial = try ReplicaSnapshot.parse(hello:["setName":c.set],status:["members":[validPrimary,initializing]])
                try check(initial.members.first{$0.name=="offline"}?.lagSeconds==nil,"在线但尚无有效 optime 的成员延迟应未知")
            }
            try await scenario(3,"三个节点各读取 10 × 50,000 文档及聚合校验") {
                for host in c.hosts {
                    let e=DatabaseEngine()
                    _ = try await e.connect(profile,secret:"mongodb://tableviewer:\(c.password)@\(host)/?directConnection=true&authSource=admin&readPreference=secondaryPreferred")
                    direct.append(e)
                    for name in ["customers","orders","products","payments","shipments","inventory","events","tickets","reviews","sessions"] {
                        try await poll { try await count(e,name)==50000 }
                    }
                    let r=try await e.run("{\"aggregate\":\"customers\",\"pipeline\":[{\"$group\":{\"_id\":null,\"sum\":{\"$sum\":\"$id\"}}}],\"cursor\":{}}")
                    let index=r.columns.firstIndex{$0.name=="sum"}!
                    try check(r.rows.first?.cells[index] == .text("1250025000"),"节点数据聚合不一致")
                }
            }
            try await scenario(4,"majority 写入在三个节点均可读取") {
                try await mark(engine,runID+"-initial")
                for e in direct { try await poll { try await count(e,"replica_receipts",id:runID+"-initial")==1 } }
            }
            try await scenario(5,"majority 更新复制至所有节点") {
                try await write(engine,"{\"update\":\"replica_receipts\",\"updates\":[{\"q\":{\"_id\":\"\(runID)-initial\"},\"u\":{\"$set\":{\"value\":2}}}],\"writeConcern\":{\"w\":\"majority\",\"wtimeout\":5000}}")
                for e in direct {
                    try await poll {
                        let r=try await e.run("{\"find\":\"replica_receipts\",\"filter\":{\"_id\":\"\(runID)-initial\"}}")
                        guard let i=r.columns.firstIndex(where:{$0.name=="value"}) else { return false }
                        return r.rows.first?.cells[i] == .text("2")
                    }
                }
            }
            try await scenario(6,"majority 删除复制至所有节点") {
                try await mark(engine,runID+"-delete")
                try await write(engine,"{\"delete\":\"replica_receipts\",\"deletes\":[{\"q\":{\"_id\":\"\(runID)-delete\"},\"limit\":1}],\"writeConcern\":{\"w\":\"majority\",\"wtimeout\":5000}}")
                for e in direct { try await poll { try await count(e,"replica_receipts",id:runID+"-delete")==0 } }
            }
            try await scenario(7,"生产 Shell worker 代码读取副本集状态与仿真数据") {
                let r=try await shell.execute("rs.status().members.map(m=>m.stateStr)",profile:profile,secret:uri)
                try check(r.ok && r.output?.contains("PRIMARY")==true && r.output?.contains("SECONDARY")==true,"Shell 副本集状态错误")
                let n=try await shell.execute("db.customers.countDocuments({})",profile:profile,secret:uri)
                try check(n.ok && n.output?.trimmingCharacters(in:.whitespacesAndNewlines)=="50000","Shell 计数错误")
            }
            var previous = try await engine.replicaSetStatus()
            try await scenario(8,"主动 stepDown 后选出不同主节点、任期递增") {
                _ = try? await admin.run("{\"replSetStepDown\":30,\"secondaryCatchUpPeriodSecs\":10}")
                try await poll {
                    let s=try await engine.replicaSetStatus()
                    let hello = try await response(engine,"{\"hello\":1}")
                    return s.primary != previous.primary && (s.term ?? 0) > (previous.term ?? 0) && hello["isWritablePrimary"] as? Bool == true
                }
                _ = try await capture(engine,"stepdown")
            }
            try await scenario(9,"原 DatabaseEngine 连接在 stepDown 后继续 majority 写入") {
                try await mark(engine,runID+"-stepdown")
                for e in direct { try await poll { try await count(e,"replica_receipts",id:runID+"-stepdown")==1 } }
            }
            previous = try await engine.replicaSetStatus()
            let oldPrimary = c.nodes[c.hosts.firstIndex(of:previous.primary)!]
            try await scenario(10,"终止当前主节点后自动选主，仍可读取 50,000 文档") {
                try docker("kill",oldPrimary); stopped.insert(oldPrimary)
                try await poll {
                    let s=try await engine.replicaSetStatus()
                    let hello = try await response(engine,"{\"hello\":1}")
                    return s.primary != previous.primary && s.members.contains{$0.name==previous.primary && $0.healthy==false} && hello["isWritablePrimary"] as? Bool == true
                }
                let s=try await capture(engine,"primary-crash")
                try check(s.members.filter{$0.healthy==true}.count==2,"存活节点应为两个")
                try check(s.members.filter{$0.healthy==false}.allSatisfy{$0.lagSeconds==nil},"离线节点不能显示虚假的复制延迟")
                try check(try await count(engine,"customers")==50000,"选主后数据计数变化")
            }
            try await scenario(11,"同一连接在主节点退出后继续 majority 写入") {
                try await mark(engine,runID+"-failover")
                try check(try await count(engine,"replica_receipts",id:runID+"-initial")==1,"原已确认记录丢失")
                try check(try await count(engine,"replica_receipts",id:runID+"-stepdown")==1,"切换前已确认记录丢失")
            }
            try await scenario(12,"旧主节点重启成为 SECONDARY 并追平故障期间写入") {
                try docker("start",oldPrimary); stopped.remove(oldPrimary)
                try await poll {
                    let s=try await engine.replicaSetStatus()
                    return s.members.allSatisfy{$0.healthy==true} && s.members.first{$0.name==previous.primary}?.role=="SECONDARY"
                }
                for e in direct { try await poll { try await count(e,"replica_receipts",id:runID+"-failover")==1 } }
                _ = try await capture(engine,"rejoined")
            }
            var secondaryIndex=0
            try await scenario(13,"从节点退出后多数派仍可写入且状态标示异常") {
                let s=try await engine.replicaSetStatus()
                let secondary=s.members.first{$0.role=="SECONDARY"}!.name
                secondaryIndex=c.hosts.firstIndex(of:secondary)!
                let node=c.nodes[secondaryIndex]
                try docker("kill",node); stopped.insert(node)
                try await poll { try await engine.replicaSetStatus().members.contains{$0.name==secondary && $0.healthy==false} }
                try await mark(engine,runID+"-secondary-outage")
                _ = try await capture(engine,"secondary-outage")
            }
            try await scenario(14,"从节点重启追平且所有节点恢复健康") {
                let node=c.nodes[secondaryIndex]
                try docker("start",node); stopped.remove(node)
                try await poll { try await engine.replicaSetStatus().members.allSatisfy{$0.healthy==true} }
                for e in direct { try await poll { try await count(e,"replica_receipts",id:runID+"-secondary-outage")==1 } }
            }
            try await scenario(15,"丢失多数派时无可写主节点，写入失败可见") {
                let s=try await engine.replicaSetStatus()
                let primaryIndex=c.hosts.firstIndex(of:s.primary)!
                for (i,node) in c.nodes.enumerated() where i != primaryIndex { try docker("kill",node); stopped.insert(node) }
                try await poll {
                    let hello=try await response(direct[primaryIndex],"{\"hello\":1}")
                    return hello["isWritablePrimary"] as? Bool == false
                }
                var rejected=false
                do { try await mark(engine,runID+"-no-majority") } catch { rejected=true }
                try check(rejected,"无多数派写入被错误确认")
            }
            try await scenario(16,"恢复多数派后原连接恢复、未确认请求未写入") {
                for node in stopped { try docker("start",node) }; stopped=[]
                try await poll {
                    let s = try await engine.replicaSetStatus()
                    let hello = try await response(engine,"{\"hello\":1}")
                    return s.members.allSatisfy{$0.healthy==true} && hello["isWritablePrimary"] as? Bool == true
                }
                try await mark(engine,runID+"-restored")
                try check(try await count(engine,"replica_receipts",id:runID+"-no-majority")==0,"无多数派期间出现未预期写入，需核对")
                _ = try await capture(engine,"restored")
            }
            try await scenario(17,"切换后原 Shell 会话继续查询新主节点") {
                let r=try await shell.execute("db.customers.countDocuments({})",profile:profile,secret:uri)
                try check(r.ok && r.output?.trimmingCharacters(in:.whitespacesAndNewlines)=="50000","Shell 故障切换后未恢复")
            }
            try await scenario(18,"三节点最终全量计数一致、已确认写入均存在") {
                for e in direct {
                    for name in ["customers","orders","products","payments","shipments","inventory","events","tickets","reviews","sessions"] {
                        try await poll { try await count(e,name)==50000 }
                    }
                    for suffix in ["initial","stepdown","failover","secondary-outage","restored"] {
                        try await poll { try await count(e,"replica_receipts",id:runID+"-"+suffix)==1 }
                    }
                }
            }
        } catch { failure=error }
        // 只恢复本测试实际停止的节点；失败也不把副本集留在降级状态。
        for node in stopped { do { try docker("start",node) } catch { print("RECOVERY FAILED \(node): \(error)"); failure=error } }
        await shell.stop(); await engine.disconnect(); await admin.disconnect()
        for e in direct { await e.disconnect() }
        try JSONSerialization.data(withJSONObject:["planned":18,"passed":records.filter{$0["status"] as? String=="passed"}.count,"run_id":runID,"scenarios":records,"snapshots":snapshots],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("results.json"))
        if let failure { print("测试未通过：\(failure.localizedDescription)"); exit(1) }
    }
}
