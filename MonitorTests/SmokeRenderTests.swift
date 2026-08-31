import SwiftUI
import XCTest
@testable import Monitor

/**
 * Tra loi thay server that cho MOI request cua URLSession.shared, chon body
 * theo duong dan. Dang ky toan cuc nen cac view (dung auth.client -> shared)
 * chay duoc trong test ma khong cham mang.
 */
final class RouterProtocol: URLProtocol {
    /// normal = du lieu day; empty = list rong; error = 500.
    enum Mode { case normal, empty, error }
    nonisolated(unsafe) static var mode = Mode.normal
    nonisolated(unsafe) static var seenPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "alert.huyab.click"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(for path: String) -> String {
        switch path {
        case "/api/me":
            return """
            {"email":"huy@a.vn","authenticated":true,"settings":{"alert_delay_minutes":30}}
            """
        case "/api/configs":
            return """
            [{"id":3,"user_email":"huy@a.vn","name":"Prod chính","url":"https://odoo.a.vn",
              "db":"prod","username":"admin","password":"secret","env":"prod",
              "alert_enabled":1,"sort_order":0},
             {"id":4,"user_email":"huy@a.vn","name":"Dev","url":"https://dev.a.vn","db":"dev",
              "username":"admin","password":"x","env":"dev","alert_enabled":0,"sort_order":1}]
            """
        case "/api/crons":
            // Mot cron tre nang, mot tre nhe, mot chua den han, mot khong model.
            return """
            {"config_name":"Prod chính","crons":[
              {"id":1,"name":"Gửi mail","nextcall":"2020-01-01 00:00:00","active":true,
               "model_id":[41,"mail.mail"]},
              {"id":2,"name":"Đồng bộ kho","nextcall":"2020-01-01 00:00:00","active":false,
               "model_id":false},
              {"id":3,"name":"Tương lai","nextcall":"2099-01-01 00:00:00","active":true,
               "model_id":[9,"res.partner"]}]}
            """
        default:
            return "{}"
        }
    }

    private static func emptyBody(for path: String) -> String {
        switch path {
        case "/api/me": return "{\"email\":null,\"authenticated\":true}"
        case "/api/configs": return "[]"
        case "/api/crons": return "{\"crons\":[]}"
        default: return "{}"
        }
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.seenPaths.append(path)
        let code = Self.mode == .error ? 500 : 200
        let body = Self.mode == .normal ? Self.body(for: path)
            : Self.mode == .empty ? Self.emptyBody(for: path) : "{}"
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class SmokeRenderTests: XCTestCase {
    private var window: UIWindow!
    private var auth: AuthStore!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(RouterProtocol.self)
        RouterProtocol.seenPaths = []
        RouterProtocol.mode = .normal
        Keychain.write(fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970))
        auth = AuthStore()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RouterProtocol.self)
        Keychain.clear()
        SsoCookie.remove()
        window = nil
        super.tearDown()
    }

    /// Dung view len that su: `body` chay, `.task` chay, decode chay. Mot man
    /// hinh vo (crash hoac decode sai kieu) la test do ngay.
    private func render(_ view: some View, seconds: TimeInterval = 0.6) async {
        let host = UIHostingController(rootView: view.environmentObject(auth))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func testRootTabs() async {
        await render(RootTabs(), seconds: 1.0)
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/me"))
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/crons"))
    }

    func testLoginView() async {
        auth.signOut(notice: "Phiên đã hết hạn, đăng nhập lại nhé.")
        await render(LoginView(), seconds: 0.2)
    }

    func testEveryTab() async {
        await render(CronsView())
        await render(ConfigsView())
        await render(SettingsView())
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/configs"))
    }

    /// Danh sach rong: moi man hinh phai hien trang thai trong chu khong vo.
    func testEmptyState() async {
        RouterProtocol.mode = .empty
        await render(CronsView())
        await render(ConfigsView())
        await render(SettingsView())
    }

    /// Server 500: nhanh hien loi.
    func testErrorState() async {
        RouterProtocol.mode = .error
        await render(CronsView())
        await render(ConfigsView())
        await render(SettingsView())
    }

    func testConfigForm() async {
        // Them moi va sua — hai nhanh cua cung mot form.
        await render(NavigationStack { ConfigForm(draft: ConfigDraft(), onSaved: {}) }, seconds: 0.2)
        let config = try? ApiClient.decoder.decode([ApiConfig].self, from: Data("""
        [{"id":3,"user_email":"a","name":"Prod","url":"u","db":"d","username":"n",
          "password":"p","env":"prod","alert_enabled":1,"sort_order":0}]
        """.utf8))
        let draft = ConfigDraft(config!.first!)
        XCTAssertEqual(draft.configId, 3)
        await render(NavigationStack { ConfigForm(draft: draft, onSaved: {}) }, seconds: 0.2)
    }
}
