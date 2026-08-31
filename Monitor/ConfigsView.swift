import SwiftUI

/// Danh sach instance Odoo. Server khong co endpoint xoa nen day chi them,
/// sua, nhan ban, doi thu tu va gui mail thu.
struct ConfigsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var configs: [ApiConfig] = []
    @State private var error: String?
    @State private var notice: String?
    @State private var editing: ConfigDraft?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                if let notice { Text(notice).foregroundStyle(.green).font(.footnote) }

                ForEach(Array(configs.enumerated()), id: \.element.id) { index, config in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(config.name)
                            Spacer()
                            Text(envLabel(config.env))
                                .font(.caption.bold())
                                .foregroundStyle(config.env == "prod" ? .red : .secondary)
                        }
                        Text("\(config.url) · \(config.db)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .swipeActions(edge: .leading) {
                        if index > 0 {
                            Button("Lên") { Task { await move(index, to: index - 1) } }.tint(.blue)
                        }
                        if index < configs.count - 1 {
                            Button("Xuống") { Task { await move(index, to: index + 1) } }.tint(.blue)
                        }
                    }
                    .swipeActions {
                        Button("Sửa") { editing = ConfigDraft(config) }.tint(.orange)
                        Button("Nhân bản") { Task { await duplicate(config) } }.tint(.indigo)
                        Button("Mail thử") { Task { await testEmail(config) } }.tint(.teal)
                    }
                }

                if configs.isEmpty && loaded {
                    Text("Chưa có instance nào. Bấm + để thêm.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Instance")
            .overlay { if !loaded { ProgressView() } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = ConfigDraft() } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(item: $editing) { draft in
                ConfigForm(draft: draft) { Task { await load() } }
            }
        }
    }

    private func load() async {
        error = await auth.perform { configs = try await $0.get("/api/configs") }
        loaded = true
    }

    private func move(_ from: Int, to: Int) async {
        var ids = configs.map(\.id)
        ids.swapAt(from, to)
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/configs/reorder",
                                                          body: ReorderInput(ids: ids))
        }
        await load()
    }

    private func duplicate(_ config: ApiConfig) async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/configs/\(config.id)/duplicate")
        }
        await load()
    }

    private func testEmail(_ config: ApiConfig) async {
        notice = nil
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/configs/\(config.id)/test-email")
        }
        if error == nil { notice = "Đã gửi mail thử cho \(config.name)." }
    }
}

/// Ban nhap cua form. `id` nil = them moi.
struct ConfigDraft: Identifiable {
    var configId: Int?
    var name = ""
    var url = ""
    var db = ""
    var username = ""
    var password = ""
    var env = "prod"

    var id: Int { configId ?? -1 }

    init() {}

    init(_ config: ApiConfig) {
        configId = config.id
        name = config.name
        url = config.url
        db = config.db
        username = config.username
        password = config.password
        env = config.env
    }
}

struct ConfigForm: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State var draft: ConfigDraft
    let onSaved: () -> Void

    @State private var error: String?
    @State private var saving = false

    private var valid: Bool {
        ![draft.name, draft.url, draft.db, draft.username].contains {
            $0.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                Section("Instance") {
                    TextField("Tên", text: $draft.name)
                    TextField("URL, vd https://odoo.abc.vn", text: $draft.url)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Database", text: $draft.db)
                        .textInputAutocapitalization(.never)
                    Picker("Môi trường", selection: $draft.env) {
                        ForEach(envOptions, id: \.id) { Text($0.label).tag($0.id) }
                    }
                }

                Section("Đăng nhập Odoo") {
                    TextField("Username", text: $draft.username)
                        .textInputAutocapitalization(.never)
                    SecureField("Password", text: $draft.password)
                }
            }
            .navigationTitle(draft.configId == nil ? "Thêm instance" : "Sửa instance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(!valid || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let body = ConfigInput(name: draft.name, url: draft.url, db: draft.db,
                               username: draft.username, password: draft.password, env: draft.env)
        error = await auth.perform { client in
            let _: ApiClient.Ignored = draft.configId == nil
                ? try await client.post("/api/configs", body: body)
                : try await client.put("/api/configs/\(draft.configId!)", body: body)
        }
        if error == nil {
            onSaved()
            dismiss()
        }
    }
}
