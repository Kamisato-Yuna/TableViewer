import Foundation
import Observation

struct SavedScript: Codable, Identifiable {
    var id = UUID()
    var connectionID: UUID
    var name: String
    var lastUsed = Date()
    var isOpen = true
    var filename: String { id.uuidString + ".sql" }
}

@MainActor @Observable final class ScriptLibrary {
    private(set) var scripts: [SavedScript] = []
    var failure: String?
    let directory: URL
    init(directory: URL = LocalWorkspace.directory.appendingPathComponent("Scripts")) {
        self.directory = directory
        do {
            let index = directory.appendingPathComponent("scripts.json")
            if FileManager.default.fileExists(atPath: index.path) { scripts = try JSONDecoder().decode([SavedScript].self, from: Data(contentsOf: index)) }
        } catch { failure = error.localizedDescription }
    }
    private func persist() throws {
        guard failure == nil else { throw DatabaseFailure(failure!) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("scripts.json")
        try JSONEncoder().encode(scripts).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func create(name: String, connectionID: UUID, text: String = "") throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && trimmed.count <= 100 else { throw DatabaseFailure("脚本名称须为 1–100 个字符。") }
        let script = SavedScript(connectionID: connectionID, name: trimmed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try text.write(to: directory.appendingPathComponent(script.filename), atomically: true, encoding: .utf8)
        scripts.append(script)
        do { try persist(); try save(script.id, text: text) } catch { scripts.removeAll { $0.id == script.id }; throw error }
        return script.id
    }
    func save(_ id: UUID, text: String) throws {
        guard let script = scripts.first(where: { $0.id == id }) else { return }
        let url = directory.appendingPathComponent(script.filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func open(_ id: UUID) throws -> String {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { throw DatabaseFailure("脚本不存在。") }
        let text = try String(contentsOf: directory.appendingPathComponent(scripts[index].filename), encoding: .utf8)
        scripts[index].lastUsed = Date(); scripts[index].isOpen = true; try persist(); return text
    }
    func rename(_ id: UUID, name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && name.count <= 100, let index = scripts.firstIndex(where: { $0.id == id }) else { throw DatabaseFailure("脚本名称须为 1–100 个字符。") }
        scripts[index].name = name; try persist()
    }
    func close(_ id: UUID) throws {
        guard let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].isOpen = false; try persist()
    }
    func unused(days: Int, now: Date = Date()) -> [SavedScript] {
        scripts.filter { !$0.isOpen && $0.lastUsed < now.addingTimeInterval(-Double(max(1, days)) * 86400) }
    }
    func delete(_ ids: Set<UUID>) throws {
        // Only files owned by this index, never paths supplied through script names.
        for script in scripts.filter({ ids.contains($0.id) }) {
            let url = directory.appendingPathComponent(script.filename)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            scripts.removeAll { $0.id == script.id }; try persist()
        }
    }
}
