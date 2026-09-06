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
                            TextEditor(text: $store.documentDraft).font(.system(size: 11, design: .monospaced))
                                .scrollContentBackground(.hidden).frame(minHeight: 420).disabled(!store.canEdit || store.busy)
                                .accessibilityLabel("MongoDB 文档")
                        } else {
                            ForEach(Array(store.result.columns.enumerated()), id: \.element.id) { index, column in
                                if index < store.draft.count {
                                    field(index: index, column: column, original: row.cells[index])
                                }
                            }
                        }
                    }.padding(20)
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
            }
        }
    }

    private func field(index: Int, column: ColumnInfo, original: CellValue) -> some View {
        let editable = store.canEdit && column.isEditable && !column.isPrimaryKey && !isBlob(original)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if column.isPrimaryKey { Image(systemName: "key.horizontal").foregroundStyle(.orange).font(.system(size: 10)) }
                Text(column.name).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 4)
                Text(column.type.isEmpty ? "TEXT" : column.type.uppercased()).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            TextField("NULL", text: Binding(get: { store.draft[index].isNull ? "" : store.draft[index].display }, set: { store.draft[index] = .text($0) }), axis: .vertical)
                .font(.system(size: 12, design: column.isPrimaryKey ? .monospaced : .default))
                .lineLimit(1...6).textFieldStyle(.plain).padding(10)
                .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(store.draft[index] != original ? Color.orange.opacity(0.45) : Color.primary.opacity(0.06)) }
                .disabled(!editable || store.busy || store.draft[index].isNull)
                .accessibilityLabel("字段 \(column.name)")
            if editable {
                Toggle("NULL", isOn: Binding(get: { store.draft[index].isNull }, set: { store.draft[index] = $0 ? .null : .text(original.string ?? "") }))
                    .toggleStyle(.checkbox).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).disabled(store.busy)
            }
        }
    }
    private func isBlob(_ value: CellValue) -> Bool { if case .blob = value { true } else { false } }
}

struct StructureView: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(store.active?.kind == .mongodb ? String(localized: "当前页文档字段") : String(localized: "表结构")).font(.system(size: 12, weight: .medium)); Spacer(); Text("\(store.result.columns.count) 个字段").foregroundStyle(.secondary) }.padding(24)
            Table(store.result.columns) {
                TableColumn("字段") { column in Label(column.name, systemImage: column.isPrimaryKey ? "key.horizontal" : "text.alignleft").font(.system(size: 12, design: .monospaced)) }
                TableColumn("类型") { Text($0.type).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                TableColumn("主键") { Text($0.isPrimaryKey ? String(localized: "是") : "—").foregroundStyle(.secondary) }.width(60)
                TableColumn("默认值") { Text($0.defaultValue ?? "—").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
                TableColumn("写入") { Text($0.isEditable ? String(localized: "可编辑") : String(localized: "自动生成")).font(.system(size: 11)).foregroundStyle(.secondary) }.width(80)
            }
        }
    }
}
