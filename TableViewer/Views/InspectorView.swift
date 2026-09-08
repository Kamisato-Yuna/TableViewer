import SwiftUI

struct InspectorView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("记录详情").font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.selectedRow != nil {
                    Text(store.hasChanges ? String(localized: "已修改") : String(localized: "\(store.result.columns.count) 个字段"))
                        .font(.system(size: 10)).foregroundStyle(store.hasChanges ? Color.orange : Color.secondary)
                }
            }.padding(20)
            Divider()
            if store.tab != .data {
                ContentUnavailableView("专注于\(store.tab.title)", systemImage: store.tab == .query ? "terminal" : "square.stack.3d.up", description: Text("返回数据页选择一条记录，查看和编辑字段。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let row = store.selectedRow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 10) {
                            Image(systemName: store.active?.kind == .mongodb ? "curlybraces" : "rectangle.and.pencil.and.ellipsis")
                                .font(.system(size: 20, weight: .light)).foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.selectedObject?.name ?? String(localized: "记录")).font(.system(size: 14, weight: .medium))
                                Text(store.canEdit ? String(localized: "编辑后按 ⌘S 保存") : String(localized: "只读 · 视图或无主键的表")).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 2)
                        if store.active?.kind == .mongodb {
                            Text("EXTENDED JSON").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
                            TextEditor(text: store.documentBinding(row: row)).font(.system(size: 11, design: .monospaced))
                                .scrollContentBackground(.hidden).frame(minHeight: 420).disabled(!store.canEdit || store.busy)
                                .accessibilityLabel("MongoDB 文档")
                        } else {
                            ForEach(Array(store.result.columns.enumerated()), id: \.element.id) { index, column in
                                if store.draft.indices.contains(index), row.cells.indices.contains(index) {
                                    field(row: row, index: index, column: column, original: row.cells[index])
                                }
                            }
                        }
                    }.padding(20).id(row.id)
                }
                Spacer(minLength: 0)
                Divider()
                HStack {
                    Button(role: .destructive) { store.showDelete = true } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).help("删除记录").disabled(!store.canEdit || store.busy || store.hasChanges)
                    Spacer()
                    Button("撤销") { store.discard() }.disabled(!store.hasChanges || store.busy)
                    Button("保存") { Task { await store.saveRow() } }.buttonStyle(.glassProminent)
                        .disabled(!store.hasChanges || store.busy || !store.canEdit)
                }.controlSize(.small).padding(16)
            } else {
                ContentUnavailableView("选择一条记录", systemImage: "cursorarrow.click.2", description: Text("字段、类型和编辑选项会显示在这里。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func field(row: DataRow, index: Int, column: ColumnInfo, original: CellValue) -> some View {
        let editable = store.canEdit && column.isEditable && !column.isPrimaryKey && !isBlob(original)
        let value = store.fieldBinding(row: row, index: index, column: column)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if column.isPrimaryKey { Image(systemName: "key.horizontal").foregroundStyle(.orange).font(.system(size: 10)) }
                Text(column.name).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text(column.type.isEmpty ? "TEXT" : column.type.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            TextField(value.wrappedValue.isNull ? "NULL" : "", text: Binding(get: { value.wrappedValue.isNull ? "" : value.wrappedValue.display }, set: { value.wrappedValue = .text($0) }), axis: .vertical)
                .font(.system(size: 12, design: column.isPrimaryKey ? .monospaced : .default))
                .lineLimit(1...6).textFieldStyle(.plain).padding(10)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(value.wrappedValue != original ? Color.orange.opacity(0.45) : Color.primary.opacity(0.06)) }
                .disabled(!editable || store.busy || value.wrappedValue.isNull)
                .accessibilityLabel("字段 \(column.name)")
            if editable {
                Toggle("NULL", isOn: Binding(get: { value.wrappedValue.isNull }, set: { value.wrappedValue = $0 ? .null : .text(original.string ?? "") }))
                    .toggleStyle(.checkbox).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).disabled(store.busy)
            }
        }
    }
    private func isBlob(_ value: CellValue) -> Bool { if case .blob = value { true } else { false } }
}
