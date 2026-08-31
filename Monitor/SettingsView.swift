import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email: String?
    @State private var minutes = 30
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                Section("Tài khoản") {
                    LabeledContent("Email", value: email ?? "…")
                }

                Section {
                    Stepper("Trễ \(minutes) phút thì báo", value: $minutes, in: 1...1440, step: 5)
                        .onChange(of: minutes) { _ in saved = false }
                    Button(saved ? "Đã lưu" : "Lưu") { Task { await save() } }
                } header: {
                    Text("Ngưỡng cảnh báo")
                } footer: {
                    Text("Cron quá hạn lâu hơn mức này sẽ được gửi mail. Server kiểm mỗi phút.")
                }

                Section {
                    Button(role: .destructive) { auth.signOut() } label: {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .task { await load() }
        }
    }

    private func load() async {
        error = await auth.perform {
            let me: ApiMe = try await $0.get("/api/me")
            email = me.email
            minutes = me.settings?.alertDelayMinutes ?? 30
        }
    }

    private func save() async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.put("/api/settings",
                                                        body: SettingsInput(alertDelayMinutes: minutes))
        }
        saved = error == nil
    }
}
