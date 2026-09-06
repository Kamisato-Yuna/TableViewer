import Foundation
import Security

enum ConnectionVault {
    static let service = "local.yuna.TableViewer.connections"
    static func save(_ secret: String, id: UUID) throws {
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
    static func read(id: UUID) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data else { throw DatabaseFailure(String(localized: "无法读取钥匙串凭据（\(status)）。")) }
        return String(decoding: data, as: UTF8.self)
    }
    static func remove(id: UUID) throws {
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
