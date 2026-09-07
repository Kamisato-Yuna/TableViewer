import SwiftUI
import UniformTypeIdentifiers

struct StructureMetadataView: View {
    var metadata: SchemaMetadata
    var object: DatabaseObject
    var kind: DatabaseKind
    @State private var filter = "全部"
    @State private var search = ""
    @State private var showDDL = false
    @State private var error: String?
    private var fields: [SchemaField] {
        metadata.fields.filter { field in
            (search.isEmpty || field.name.localizedCaseInsensitiveContains(search)) &&
            (filter == "全部" || field.constraints.contains { $0.contains(filter) })
        }
    }
    private var filters: [String] { ["全部"] + Array(Set(metadata.fields.flatMap(\.constraints))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("结构 · \(object.name)").font(.headline)
                Spacer()
                Button(String(localized: kind == .mongodb ? "查看定义" : "查看 DDL")) { showDDL = true }
                Button("导出") { exportDefinition() }.disabled(metadata.ddl.isEmpty)
            }
            HStack {
                TextField("查找字段", text: $search).textFieldStyle(.roundedBorder)
                Picker("约束", selection: $filter) { ForEach(filters, id: \.self) { Text($0 == "全部" ? String(localized: "全部") : $0).tag($0) } }.frame(maxWidth: 250)
            }
            Table(fields) {
                TableColumn("字段") { Text($0.name).font(.system(.body, design: .monospaced)) }
                TableColumn("类型") { Text($0.type).foregroundStyle(.secondary) }
                TableColumn("约束") { Text($0.constraints.joined(separator: " · ")) }
                TableColumn("默认值") { Text($0.defaultValue ?? "—").font(.system(.body, design: .monospaced)) }
            }.frame(minHeight: 150)
            DisclosureGroup("索引（\(metadata.indexes.count)）") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(metadata.indexes) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(index.name, systemImage: index.unique ? "key" : "list.bullet").font(.subheadline.bold())
                                Text(index.definition).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 180)
            }
            if !metadata.notice.isEmpty { Text(metadata.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }.padding(24)
        .sheet(isPresented: $showDDL) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(String(localized: kind == .mongodb ? "集合定义" : "DDL")).font(.headline); Spacer(); Button("导出") { exportDefinition() }; Button("完成") { showDDL = false }.keyboardShortcut(.cancelAction) }
                ScrollView([.horizontal, .vertical]) { Text(metadata.ddl).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(24).frame(minWidth: 640, minHeight: 420)
        }
        .alert("无法导出", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func exportDefinition() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = object.name + (kind == .mongodb ? ".json" : ".sql")
        panel.allowedContentTypes = kind == .mongodb ? [.json] : [UTType(filenameExtension: "sql") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try metadata.ddl.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
}
