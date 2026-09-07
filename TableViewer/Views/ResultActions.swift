import SwiftUI

struct ExportMenu: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        Menu {
            ForEach(ResultExportFormat.allCases.filter { $0 != .sql }) { format in
                Button(format.title) { store.exportResult(format) }
            }
            Menu("INSERT SQL") {
                ForEach(ResultSQLDialect.allCases) { dialect in Button(dialect.rawValue) { store.exportResult(.sql, dialect: dialect) } }
            }.disabled(store.active?.kind == .mongodb)
        } label: { Label("导出", systemImage: "square.and.arrow.up") }
        .disabled(store.displayedResult.columns.isEmpty)
    }
}

struct CellEditorSheet: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let row = store.selectedRow, let index = store.editingCellIndex, store.result.columns.indices.contains(index) {
                let column = store.result.columns[index]
                let binding = store.fieldBinding(row: row, index: index, column: column)
                Text(column.name).font(.title2)
                if store.active?.kind == .mongodb {
                    Text("MongoDB 单元格使用 JSON 值，字符串需要双引号；此处仅更新所选字段。").font(.caption)
                    MongoCellField(store: store, row: row, column: column)
                } else {
                    TextField("值", text: Binding(get: { binding.wrappedValue.string ?? "" }, set: { binding.wrappedValue = .text($0) }), axis: .vertical).lineLimit(3...10).textFieldStyle(.roundedBorder).disabled(binding.wrappedValue.isNull)
                    Toggle("NULL", isOn: Binding(get: { binding.wrappedValue.isNull }, set: { binding.wrappedValue = $0 ? .null : .text("") }))
                }
                HStack { Spacer(); Button("取消") { store.discard(); dismiss() }; Button("保存") { Task { await store.saveRow(); if !store.hasChanges { dismiss() } } }.buttonStyle(.glassProminent).disabled(store.readOnly || store.busy || !store.hasChanges) }
            }
        }.padding(24).frame(width: 480)
    }
}

private struct MongoCellField: View {
    @Bindable var store: WorkspaceStore
    let row: DataRow
    let column: ColumnInfo
    @State private var value = ""
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading) {
            TextField("JSON 值", text: $value, axis: .vertical).lineLimit(3...10).textFieldStyle(.roundedBorder)
                .onChange(of: value) { _, text in
                    do {
                        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
                        var document = try jsonObject(row.document ?? "{}")
                        document[column.name] = parsed
                        store.documentDraft = try jsonText(document, pretty: true); failure = nil
                    } catch { failure = error.localizedDescription; store.discard() }
                }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }.onAppear {
            if let object = try? jsonObject(row.document ?? "{}"), let original = object[column.name] { value = (try? jsonText(original)) ?? "null" }
        }
    }
}
