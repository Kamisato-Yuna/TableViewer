import Foundation
import Security
import AppKit

/// Only successful reads/writes are reused, and only in this process.
/// Separate locks let a security notification invalidate an in-flight Keychain operation.
final class CredentialSessionStore: @unchecked Sendable {
    private let operations = NSLock()
    private let state = NSLock()
    private var values: [UUID: String] = [:]
    private var revision = 0
    private var enabled: Bool
    private let load: (UUID) throws -> String?
    private let persist: (String, UUID) throws -> Void
    private let delete: (UUID) throws -> Void

    init(enabled: Bool = true, load: @escaping (UUID) throws -> String?, persist: @escaping (String, UUID) throws -> Void, delete: @escaping (UUID) throws -> Void) {
        self.enabled = enabled; self.load = load; self.persist = persist; self.delete = delete
    }
    func setEnabled(_ enabled: Bool) {
        state.withLock { self.enabled = enabled; values.removeAll(); revision += 1 }
    }
    func clear() {
        state.withLock { values.removeAll(); revision += 1 }
    }
    func read(id: UUID) throws -> String {
        operations.lock(); defer { operations.unlock() }
        let (cached, version) = state.withLock { (values[id], revision) }
        if let cached { return cached }
        guard let secret = try load(id) else { return "" } // Missing items must remain retryable.
        remember(secret, id: id, version: version)
        return secret
    }
    func save(_ secret: String, id: UUID) throws {
        operations.lock(); defer { operations.unlock() }
        let unchanged = state.withLock { values[id] == secret }
        if unchanged { return }
        let version = state.withLock { values[id] = nil; return revision }
        try persist(secret, id)
        remember(secret, id: id, version: version)
    }
    func remove(id: UUID) throws {
        operations.lock(); defer { operations.unlock() }
        state.withLock { values[id] = nil }
        try delete(id)
    }
    private func remember(_ secret: String, id: UUID, version: Int) {
        state.withLock {
            // A lock/sleep notification during the system prompt must win over its completion.
            if enabled && revision == version { values[id] = secret }
        }
    }
}

enum ConnectionVault {
    static let service = "local.yuna.TableViewer.connections"
    private static let credentials = CredentialSessionStore(enabled: false, load: readKeychain, persist: saveKeychain, delete: removeKeychain)
    @MainActor private static var observers: [NSObjectProtocol] = []
    @MainActor private static var observationStatus: OSStatus?
    @discardableResult @MainActor static func startSession() -> OSStatus {
        if let observationStatus { return observationStatus }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { _ in credentials.clear() })
        }
        // This app uses the macOS file-based Keychain. Keep its lock and external-edit
        // notifications until migrating storage; do not change existing item ACLs.
        let status = SecKeychainAddCallback({ event, info, _ in
            if event == .lockEvent || info.pointee.pid != getpid() { ConnectionVault.credentials.clear() }
            return errSecSuccess
        }, [.lockEventMask, .addEventMask, .updateEventMask, .deleteEventMask], nil)
        credentials.setEnabled(status == errSecSuccess)
        observationStatus = status
        return status
    }
    static func save(_ secret: String, id: UUID) throws {
        try credentials.save(secret, id: id)
    }
    static func read(id: UUID) throws -> String { try credentials.read(id: id) }
    static func remove(id: UUID) throws { try credentials.remove(id: id) }
    private static func saveKeychain(_ secret: String, id: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
        let data = Data(secret.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw DatabaseFailure(String(localized: "无法将连接凭据存入钥匙串（\(added)）。")) }
        } else if status != errSecSuccess { throw DatabaseFailure(String(localized: "钥匙串更新失败（\(status)）。")) }
    }
    private static func readKeychain(id: UUID) throws -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw readFailure(status) }
        return String(decoding: data, as: UTF8.self)
    }
    static func readFailure(_ status: OSStatus) -> DatabaseFailure {
        switch status {
        case errSecUserCanceled: return DatabaseFailure(String(localized: "已取消读取钥匙串凭据。"))
        case errSecAuthFailed: return DatabaseFailure(String(localized: "钥匙串未授权读取凭据，请重试并允许访问。"))
        default: return DatabaseFailure(String(localized: "无法读取钥匙串凭据（\(status)）。"))
        }
    }
    private static func removeKeychain(id: UUID) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DatabaseFailure(String(localized: "钥匙串删除失败（\(status)）。")) }
    }
}

enum LocalWorkspace {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TableViewer", isDirectory: true)
    }
    static func loadProfiles() throws -> [ConnectionProfile] {
        let url = directory.appendingPathComponent("connections.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ConnectionProfile].self, from: Data(contentsOf: url))
    }
    static func saveProfiles(_ profiles: [ConnectionProfile]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(profiles.filter { !$0.isDemo })
        let url = directory.appendingPathComponent("connections.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func createDemo() throws -> ConnectionProfile {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("Studio.sqlite").path
        if !FileManager.default.fileExists(atPath: path) {
            var db: OpaquePointer?
            guard sqlite3_open(path, &db) == SQLITE_OK else { throw DatabaseFailure(String(localized: "无法创建示例数据库。")) }
            defer { sqlite3_close(db) }
            let sql = """
            BEGIN;
            CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, status TEXT NOT NULL DEFAULT '进行中', progress INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
            CREATE TABLE members (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT UNIQUE, role TEXT NOT NULL, joined_at TEXT DEFAULT CURRENT_TIMESTAMP);
            CREATE TABLE notes (id INTEGER PRIMARY KEY, project_id INTEGER REFERENCES projects(id), title TEXT NOT NULL, content TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
            CREATE TABLE activity (id INTEGER PRIMARY KEY, project_id INTEGER REFERENCES projects(id), action TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
            INSERT INTO projects VALUES
            (1,'Aperture','品牌设计','进行中',72,'2026-09-05 16:42'),
            (2,'Forma Design System','界面设计','进行中',86,'2026-09-05 14:18'),
            (3,'Quiet Hours','macOS 应用','已完成',100,'2026-09-04 09:30'),
            (4,'Monograph','网站开发','进行中',48,'2026-09-04 11:52'),
            (5,'Field Notes','个人项目','待开始',0,'2026-09-03 18:06'),
            (6,'Objects & Spaces','摄影','进行中',64,'2026-09-03 10:24'),
            (7,'Sunday Studio','品牌设计','已完成',100,'2026-09-02 16:10'),
            (8,'Atlas Library','网站开发','进行中',35,'2026-09-02 12:48'),
            (9,'Soft Focus','摄影','待开始',0,'2026-09-01 15:22'),
            (10,'Paper Trails','个人项目','进行中',57,'2026-09-01 09:14'),
            (11,'Common Ground','品牌设计','已完成',100,'2026-08-31 17:36'),
            (12,'Orbit','macOS 应用','进行中',23,'2026-08-31 11:08');
            INSERT INTO members (name,email,role) VALUES ('Yuna','yuna@example.com','设计师'),('Alex Chen','alex@example.com','开发者'),('Mia Lin','mia@example.com','摄影师');
            INSERT INTO notes (project_id,title,content) VALUES (1,'品牌方向','温暖、克制、专注于细节。'),(2,'组件整理','整理按钮、表格和导航组件。');
            INSERT INTO activity (project_id,action) VALUES (1,'更新视觉方向'),(2,'完成组件评审'),(3,'交付版本 1.0');
            CREATE VIEW active_projects AS SELECT id,name,category,progress FROM projects WHERE status='进行中';
            COMMIT;
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseFailure(String(cString: sqlite3_errmsg(db))) }
        }
        return ConnectionProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Studio", kind: .sqlite, path: path, isDemo: true)
    }
}
