import Foundation

struct ReplicaMember: Identifiable, Sendable {
    var name: String
    var role: String
    var healthy: Bool?
    var lagSeconds: Double?
    var pingMS: Double?
    var uptime: Int?
    var syncSource: String
    var isSelf: Bool
    var heartbeatMessage: String
    var id: String { name }
}

struct ReplicaSnapshot: Sendable {
    var setName: String
    var topology: String
    var primary: String
    var members: [ReplicaMember]
    var term: Int?
    var majority: Int?
    var fetchedAt = Date()
    var notice: String?
    var rawJSON: String

    static func parse(hello: [String: Any], status: [String: Any]?, notice: String? = nil) throws -> Self {
        let name = hello["setName"] as? String ?? status?["set"] as? String ?? ""
        let topology = hello["msg"] as? String == "isdbgrid" ? String(localized: "分片路由") : name.isEmpty ? String(localized: "独立实例") : String(localized: "副本集")
        let rawMembers = status?["members"] as? [[String: Any]] ?? []
        let primary = rawMembers.first { $0["stateStr"] as? String == "PRIMARY" }
        let primaryDate = primary.flatMap { bsonDate($0["optimeDate"]) }
        var members = rawMembers.map { member in
            let date = bsonDate(member["optimeDate"])
            let lag = primaryDate.flatMap { p in date.map { max(0, p.timeIntervalSince($0)) } }
            return ReplicaMember(name: member["name"] as? String ?? String(localized: "未知节点"), role: member["stateStr"] as? String ?? "UNKNOWN", healthy: bsonNumber(member["health"]).map { $0 == 1 }, lagSeconds: lag, pingMS: bsonNumber(member["pingMs"]), uptime: member["uptime"].map { numericValue($0) }, syncSource: member["syncSourceHost"] as? String ?? "", isSelf: member["self"] as? Bool == true, heartbeatMessage: member["lastHeartbeatMessage"] as? String ?? "")
        }
        if members.isEmpty {
            let hosts = (hello["hosts"] as? [String] ?? []) + (hello["passives"] as? [String] ?? []) + (hello["arbiters"] as? [String] ?? [])
            let primaryHost = hello["primary"] as? String
            let arbiters = hello["arbiters"] as? [String] ?? []
            members = Array(Set(hosts)).sorted().map {
                ReplicaMember(name: $0, role: $0 == primaryHost ? "PRIMARY" : arbiters.contains($0) ? "ARBITER" : "UNKNOWN", healthy: nil, lagSeconds: nil, pingMS: nil, uptime: nil, syncSource: "", isSelf: $0 == hello["me"] as? String, heartbeatMessage: "")
            }
        }
        return ReplicaSnapshot(setName: name.isEmpty ? topology : name, topology: topology, primary: primary?["name"] as? String ?? hello["primary"] as? String ?? "—", members: members.sorted { ($0.role == "PRIMARY" ? "0" : "1") + $0.name < ($1.role == "PRIMARY" ? "0" : "1") + $1.name }, term: status?["term"].map { numericValue($0) }, majority: status?["majorityVoteCount"].map { numericValue($0) }, notice: notice, rawJSON: try jsonText(status ?? hello, pretty: true))
    }
}

func bsonNumber(_ value: Any?) -> Double? {
    if let number = value as? NSNumber { return number.doubleValue }
    if let object = value as? [String: String], let text = object["$numberInt"] ?? object["$numberLong"] ?? object["$numberDouble"] ?? object["$numberDecimal"] { return Double(text) }
    return nil
}

func bsonDate(_ value: Any?) -> Date? {
    guard let date = (value as? [String: Any])?["$date"] else { return nil }
    if let milliseconds = bsonNumber(date) { return Date(timeIntervalSince1970: milliseconds / 1000) }
    if let string = date as? String { return ISO8601DateFormatter().date(from: string) }
    return nil
}
