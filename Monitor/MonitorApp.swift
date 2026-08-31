import SwiftUI

@main
struct MonitorApp: App {
    @StateObject private var auth = AuthStore()

    init() {
        #if DEBUG
        selfCheck()
        #endif
    }

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

#if DEBUG
/// Kiem tra nhanh hai cho de sai am tham: doc `exp` cua JWT va tinh do tre.
/// Chay luc khoi dong ban Debug — sai la crash ngay tren simulator.
private func selfCheck() {
    // {"exp":2000000000} base64url, khong padding — dung dang SSO tra ve.
    let future = "header.eyJleHAiOjIwMDAwMDAwMDB9.sig"
    assert(SsoToken.expiry(future) == Date(timeIntervalSince1970: 2_000_000_000))
    assert(SsoToken.isUsable(future))
    assert(!SsoToken.isUsable("header.eyJleHAiOjEwMDAwMDAwMDB9.sig"))
    assert(SsoToken.expiry("a.b.c") == nil)

    // 12:00:00 UTC la moc; nextcall khong co "Z" nhung van phai hieu la UTC.
    let now = Date(timeIntervalSince1970: 1_755_000_000)          // 2025-08-12T12:00:00Z
    assert(parseOdoo("2025-08-12 12:00:00") == now)
    assert(delayText("2025-08-12 12:00:00", now: now) == nil)     // dung han, chua tre
    assert(delayText("2025-08-12 11:55:00", now: now) == "trễ 5m")
    assert(delayText("2025-08-12 10:00:00", now: now) == "trễ 2h")
    assert(!isLate("2025-08-12 11:55:00", thresholdMinutes: 30, now: now))
    assert(isLate("2025-08-12 11:20:00", thresholdMinutes: 30, now: now))
}
#endif
