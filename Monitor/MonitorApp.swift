import SwiftUI

@main
struct MonitorApp: App {
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            // Mot cong duy nhat: co token thi vao app, khong thi man dang nhap.
            // Moi view goi auth.signOut() khi gap 401 nen het han la tu quay ve day.
            if auth.token == nil {
                LoginView().environmentObject(auth)
            } else {
                RootTabs().environmentObject(auth)
            }
        }
    }
}

struct RootTabs: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        TabView {
            CronsView()
                .tabItem { Label("Cron", systemImage: "clock.badge.exclamationmark") }
            ConfigsView()
                .tabItem { Label("Instance", systemImage: "server.rack") }
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
        }
        .environmentObject(auth)
    }
}
