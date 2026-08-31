import SwiftUI

/// Man chinh: chon instance roi nhin danh sach cron, tre nhat len dau mat.
/// Tu tai lai moi 30 giay giong ban web.
struct CronsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var configs: [ApiConfig] = []
    @State private var selected: Int?
    @State private var crons: [ApiCron] = []
    @State private var threshold = 30
    @State private var error: String?
    @State private var loading = false
    @State private var onlyLate = false
    @State private var search = ""

    /// Sap theo nextcall tang dan — cai sap chay (hoac tre nhat) nam tren.
    private var rows: [ApiCron] {
        crons
            .filter { !onlyLate || isLate($0.nextcall, thresholdMinutes: threshold) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { $0.nextcall < $1.nextcall }
    }

    private var lateCount: Int {
        crons.filter { isLate($0.nextcall, thresholdMinutes: threshold) }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                Section {
                    Picker("Instance", selection: $selected) {
                        Text("Chưa chọn").tag(Int?.none)
                        ForEach(configs) { config in
                            Text("\(config.name) · \(envLabel(config.env))").tag(Int?.some(config.id))
                        }
                    }
                    Toggle("Chỉ cron trễ", isOn: $onlyLate)
                } footer: {
                    Text(lateCount > 0
                         ? "\(lateCount) cron trễ quá \(threshold) phút."
                         : "Không có cron nào trễ quá \(threshold) phút.")
                }

                Section("Cron (\(rows.count))") {
                    ForEach(rows) { cron in
                        CronRow(cron: cron, late: isLate(cron.nextcall, thresholdMinutes: threshold))
                    }
                    if rows.isEmpty && !loading {
                        Text(crons.isEmpty ? "Chưa có cron nào." : "Không có cron khớp.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Tìm cron")
            .navigationTitle("Cron")
            .overlay { if loading && crons.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .task { await bootstrap() }
            // Doi instance la tai lai ngay, va bat lai dong ho 30 giay.
            .task(id: selected) {
                guard selected != nil else { return }
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
        }
    }

    private func bootstrap() async {
        error = await auth.perform { client in
            let me: ApiMe = try await client.get("/api/me")
            threshold = me.settings?.alertDelayMinutes ?? 30
            configs = try await client.get("/api/configs")
            // Server tu lay config moi nhat khi khong truyen config_id, nhung
            // chon san cai dau cho picker khong bi trong.
            if selected == nil { selected = configs.first?.id }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let query = selected.map { "?config_id=\($0)" } ?? ""
        error = await auth.perform { client in
            let list: ApiCronList = try await client.get("/api/crons\(query)")
            crons = list.crons
        }
    }
}

private struct CronRow: View {
    let cron: ApiCron
    let late: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(cron.name).font(.subheadline)
                Spacer(minLength: 8)
                if let delay = delayText(cron.nextcall) {
                    Text(delay)
                        .font(.caption.bold())
                        .foregroundStyle(late ? .red : .orange)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.caption2)
                Text(formatOdooDateTime(cron.nextcall)).monospacedDigit()
                if let model = cron.modelId?.name, !model.isEmpty {
                    Text("· \(model)").lineLimit(1)
                }
                if !cron.active {
                    Text("· tắt").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
