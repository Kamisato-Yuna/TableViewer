import SwiftUI

/// Database landing page: a searchable catalog, without selecting the first table.
struct ObjectBrowserView: View {
    var objects: [DatabaseObject]
    var kind: DatabaseKind
    var openObject: (DatabaseObject) -> Void
    @State private var search = ""
    @State private var category = "全部"
    private var visible: [DatabaseObject] {
        objects.filter { object in
            (search.isEmpty || (object.schema + "." + object.name).localizedCaseInsensitiveContains(search)) &&
            (category == "全部" || (category == "视图" ? object.isView : !object.isView))
        }.sorted { ($0.schema, $0.name) < ($1.schema, $1.name) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("数据库对象").font(.title2.bold())
                    Text("\(objects.count) 个对象").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("分类", selection: $category) {
                    Text("全部").tag("全部")
                    Text(String(localized: kind == .mongodb ? "集合" : "表")).tag("表")
                    Text("视图").tag("视图")
                }.frame(width: 160)
            }
            TextField("查找名称或架构", text: $search).textFieldStyle(.roundedBorder)
            List {
                ForEach(Array(Set(visible.map(\.schema))).sorted(), id: \.self) { schema in
                    Section(schema.isEmpty ? String(localized: kind == .mongodb ? "集合与视图" : "表与视图") : schema) {
                        ForEach(visible.filter { $0.schema == schema }) { object in
                            Button { openObject(object) } label: {
                                HStack {
                                    Label(object.name, systemImage: object.isView ? "eye" : "tablecells")
                                    Spacer()
                                    Text(String(localized: object.isView ? "视图" : (kind == .mongodb ? "集合" : "表"))).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }.padding(.vertical, 3).contentShape(Rectangle())
                            }.buttonStyle(.plain).help("打开 \(object.name)")
                        }
                    }
                }
            }.overlay { if visible.isEmpty { ContentUnavailableView("没有匹配的对象", systemImage: "magnifyingglass") } }
        }.padding(24)
    }
}

struct RelationshipView: View {
    var relationships: [TableRelationship]
    var kind: DatabaseKind
    var openObject: (DatabaseObject) -> Void
    @State private var search = ""
    private var visible: [TableRelationship] {
        relationships.filter { search.isEmpty || ($0.name + $0.source.id + $0.target.id).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("实体关系").font(.title2.bold())
            Text("显示数据库声明的外键：引用字段 → 被引用字段。点击表名可打开对象。").foregroundStyle(.secondary)
            TextField("查找表或外键", text: $search).textFieldStyle(.roundedBorder)
            if visible.isEmpty {
                ContentUnavailableView(String(localized: kind == .mongodb ? "MongoDB 没有声明式外键" : "没有匹配的外键关系"), systemImage: "point.3.connected.trianglepath.dotted", description: Text("不根据字段名称或数据值推断关系。"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(visible) { relationship in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(relationship.name).font(.caption).foregroundStyle(.secondary)
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) {
                                        entity(relationship.source, columns: relationship.sourceColumns)
                                        Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityLabel("引用")
                                        entity(relationship.target, columns: relationship.targetColumns)
                                    }
                                    VStack(alignment: .leading, spacing: 8) {
                                        entity(relationship.source, columns: relationship.sourceColumns)
                                        Image(systemName: "arrow.down").foregroundStyle(.secondary).accessibilityLabel("引用")
                                        entity(relationship.target, columns: relationship.targetColumns)
                                    }
                                }
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }.padding(24)
    }
    private func entity(_ object: DatabaseObject, columns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { openObject(object) } label: { Label(object.schema.isEmpty ? object.name : object.schema + "." + object.name, systemImage: "tablecells").fontWeight(.medium) }.buttonStyle(.link)
            Text(columns.joined(separator: ", ")).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }.padding(12).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}
