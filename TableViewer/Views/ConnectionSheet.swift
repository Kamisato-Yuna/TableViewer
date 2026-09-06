import SwiftUI
import UniformTypeIdentifiers

struct ConnectionSheet: View {
    @Bindable var store: WorkspaceStore
    let existing: ConnectionProfile?
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ConnectionProfile()
    @State private var secret = ""
    @State private var testing = false
    @State private var testMessage = ""
    @State private var testSucceeded = false
    @State private var revealURI = false
    private var valid: Bool {
        !profile.name.trimmingCharacters(in: .whitespaces).isEmpty && (profile.kind == .sqlite ? !profile.path.isEmpty : !profile.database.isEmpty && (profile.kind == .mongodb ? secret.hasPrefix("mongodb://") || secret.hasPrefix("mongodb+srv://") : !profile.host.isEmpty && Int(profile.port).map { (1...65535).contains($0) } == true))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "externaldrive.badge.plus").font(.system(size: 28, weight: .light)).foregroundStyle(.tint)
                    .frame(width: 58, height: 58).glassEffect(in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) { Text(existing == nil ? String(localized: "连接你的数据库") : String(localized: "编辑连接")).font(.system(size: 23, weight: .semibold, design: .rounded)); Text("为下一个灵感，打开数据的入口。").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
            }.padding(28)
            HStack(spacing: 12) {
                ForEach(DatabaseKind.allCases) { kind in
                    Button {
                        profile.kind = kind; profile.port = kind.defaultPort
                        profile.database = kind == .postgresql ? "postgres" : "test"
                        secret = kind == .mongodb ? "mongodb://localhost:27017" : ""
                        testMessage = ""
                    } label: {
                        VStack(spacing: 10) { Image(systemName: kind.symbol).font(.system(size: 25, weight: .light)); Text(kind.rawValue).font(.system(size: 12, weight: .medium)) }
                            .frame(maxWidth: .infinity).frame(height: 87)
                            .contentShape(.rect(cornerRadius: 12))
                            .foregroundStyle(profile.kind == kind ? Color.accentColor : Color.secondary)
                            .background(profile.kind == kind ? Color.accentColor.opacity(0.08) : Color.clear, in: .rect(cornerRadius: 12))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(profile.kind == kind ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.09)) }
                    }.buttonStyle(.plain).disabled(existing != nil || testing)
                }
            }.padding(.horizontal, 28)
            Form {
                Section {
                    TextField("连接名称", text: $profile.name, prompt: Text("例如：我的项目"))
                    if profile.kind == .sqlite {
                        LabeledContent("数据库文件") {
                            HStack {
                                Text(profile.path.isEmpty ? String(localized: "尚未选择") : URL(fileURLWithPath: profile.path).lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                                Button("选择…") { selectSQLite(create: false) }
                                Button("新建…") { selectSQLite(create: true) }
                            }
                        }
                        if !profile.path.isEmpty { Text(profile.path).font(.system(size: 10)).foregroundStyle(.tertiary).textSelection(.enabled) }
                    } else if profile.kind == .postgresql {
                        TextField("主机", text: $profile.host)
                        TextField("端口", text: $profile.port)
                        TextField("数据库", text: $profile.database)
                        TextField("用户名", text: $profile.user)
                        SecureField("密码", text: $secret)
                        Picker("TLS", selection: $profile.sslMode) {
                            Text("优先使用 TLS").tag("prefer")
                            Text("要求加密").tag("require")
                            Text("验证证书和主机").tag("verify-full")
                            Text("禁用（仅受信任本地网络）").tag("disable")
                        }
                    } else {
                        if revealURI { TextField("连接 URI", text: $secret) } else { SecureField("连接 URI", text: $secret) }
                        Toggle("显示 URI", isOn: $revealURI).font(.system(size: 11))
                        TextField("数据库", text: $profile.database)
                        Text("支持 mongodb:// 和 mongodb+srv://；认证、TLS 与副本集选项可写入 URI。").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped).scrollDisabled(true).frame(height: profile.kind == .postgresql ? 322 : profile.kind == .mongodb ? 245 : 170).disabled(testing)
            if !testMessage.isEmpty {
                HStack(alignment: .top, spacing: 6) { Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.circle"); Text(testMessage).textSelection(.enabled); Spacer() }
                    .font(.system(size: 11)).foregroundStyle(testSucceeded ? Color.green : Color.orange).padding(.horizontal, 28).padding(.bottom, 14)
            }
            HStack(spacing: 10) {
                if profile.kind != .sqlite { Label("凭据仅保存在钥匙串", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(.tertiary) }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }.disabled(testing)
                Button(testing ? String(localized: "连接中…") : String(localized: "测试连接")) { Task { await testConnection() } }.disabled(!valid || testing)
                Button("保存并连接") { saveAndConnect() }.buttonStyle(.glassProminent).disabled(!valid || testing || store.busy || store.hasChanges)
            }.controlSize(.regular).padding(24)
        }.frame(width: 590)
        .onAppear {
            if let existing {
                profile = existing
                if existing.kind != .sqlite {
                    do { secret = try ConnectionVault.read(id: existing.id) } catch { testMessage = error.localizedDescription }
                }
            }
        }
    }

    private func selectSQLite(create: Bool) {
        let panel: NSSavePanel = create ? NSSavePanel() : NSOpenPanel()
        if let open = panel as? NSOpenPanel { open.canChooseDirectories = false; open.allowsMultipleSelection = false }
        else { panel.nameFieldStringValue = "Untitled.sqlite" }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let directory = url.deletingLastPathComponent()
        let folderPanel = NSOpenPanel()
        folderPanel.canChooseFiles = false; folderPanel.canChooseDirectories = true; folderPanel.allowsMultipleSelection = false
        folderPanel.directoryURL = directory
        folderPanel.message = String(localized: "SQLite 需要在同一文件夹读写 WAL、SHM 和事务日志。请授权数据库所在文件夹：\(directory.lastPathComponent)")
        folderPanel.prompt = String(localized: "授权文件夹")
        guard folderPanel.runModal() == .OK, let authorized = folderPanel.url else { return }
        guard authorized.resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else {
            testSucceeded = false; testMessage = String(localized: "请选择数据库所在的文件夹。"); return
        }
        let directoryBookmark: Data
        do {
            directoryBookmark = try authorized.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch { testSucceeded = false; testMessage = String(localized: "无法保存文件授权：") + error.localizedDescription; return }
        if create {
            var database: OpaquePointer?
            let code = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            defer { sqlite3_close(database) }
            guard code == SQLITE_OK else { testMessage = String(localized: "无法创建 SQLite 文件。"); return }
            // Force SQLite to write a valid header even when the database has no tables yet.
            guard sqlite3_exec(database, "PRAGMA user_version = 0", nil, nil, nil) == SQLITE_OK else { testMessage = String(localized: "无法初始化 SQLite 文件。"); return }
        }
        do { profile.fileBookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { testSucceeded = false; testMessage = String(localized: "无法保存文件授权：") + error.localizedDescription; return }
        profile.directoryBookmark = directoryBookmark
        profile.path = url.path
        if profile.name.isEmpty { profile.name = url.deletingPathExtension().lastPathComponent }
        testMessage = ""
    }

    private func testConnection() async {
        testing = true; testMessage = ""
        let engine = DatabaseEngine()
        do { let objects = try await engine.connect(profile, secret: secret); testSucceeded = true; testMessage = String(localized: "连接成功 · 发现 \(objects.count) 个表 / 集合") }
        catch { testSucceeded = false; testMessage = error.localizedDescription }
        await engine.disconnect(); testing = false
    }

    private func saveAndConnect() {
        do {
            if profile.kind == .mongodb {
                let parts = URLComponents(string: secret)
                profile.host = parts?.host ?? "MongoDB"; profile.port = parts?.port.map(String.init) ?? "27017"
            }
            try store.saveConnection(profile, secret: secret)
            let saved = profile, credential = secret
            dismiss()
            Task { await store.connect(saved, secret: credential) }
        } catch { testSucceeded = false; testMessage = error.localizedDescription }
    }
}

struct InsertSheet: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var included: Set<String> = []
    @State private var nulls: Set<String> = []
    @State private var document = "{\n  \"name\": \"\"\n}"
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) { Text("添加记录").font(.system(size: 23, weight: .semibold, design: .rounded)); Text(store.selectedObject?.name ?? "").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary) }
            if store.active?.kind == .mongodb {
                Text("输入 Extended JSON 文档；省略 _id 时由 MongoDB 生成。").font(.system(size: 11)).foregroundStyle(.secondary)
                CodeEditor(text: $document, isJSON: true).frame(height: 310)
            } else {
                Text("勾选要填写的字段，未勾选的字段使用数据库默认值。").font(.system(size: 11)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(store.result.columns.filter(\.isEditable)) { column in
                            HStack(alignment: .center, spacing: 12) {
                                Toggle(column.name, isOn: Binding(get: { included.contains(column.name) }, set: { if $0 { included.insert(column.name) } else { included.remove(column.name) } }))
                                    .toggleStyle(.checkbox).font(.system(size: 11, design: .monospaced)).frame(width: 145, alignment: .leading)
                                TextField(column.defaultValue ?? column.type, text: Binding(get: { values[column.name] ?? "" }, set: { values[column.name] = $0; included.insert(column.name) }))
                                    .disabled(nulls.contains(column.name)).textFieldStyle(.roundedBorder)
                                Toggle("NULL", isOn: Binding(get: { nulls.contains(column.name) }, set: { if $0 { nulls.insert(column.name); included.insert(column.name) } else { nulls.remove(column.name) } }))
                                    .toggleStyle(.checkbox).font(.system(size: 10)).frame(width: 62)
                            }
                        }
                    }.padding(.vertical, 8)
                }.frame(maxHeight: 340)
            }
            if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
            HStack { Spacer(); Button("取消", role: .cancel) { dismiss() }; Button("添加记录") { Task { await insert() } }.buttonStyle(.glassProminent) }.disabled(store.busy)
        }.padding(28).frame(width: 610)
    }
    private func insert() async {
        let fields = store.result.columns.filter { included.contains($0.name) }.map { ($0.name, nulls.contains($0.name) ? CellValue.null : .text(values[$0.name] ?? "")) }
        if await store.insert(fields: fields, document: document) { dismiss() }
        else { failure = store.error; store.error = nil }
    }
}
