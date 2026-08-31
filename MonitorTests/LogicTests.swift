import XCTest
@testable import Monitor

/// JWT gia: chi phan payload la thuc, chu ky la rac — app khong verify chu ky.
func fakeJwt(exp: TimeInterval?, extra: String = "") -> String {
    var claims = extra
    if let exp { claims += "\"exp\":\(exp)" }
    let payload = Data("{\(claims)}".utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
}

final class SsoTokenTests: XCTestCase {
    func testExpiryReadsExpClaim() {
        let exp = Date().addingTimeInterval(3600).timeIntervalSince1970.rounded()
        XCTAssertEqual(SsoToken.expiry(fakeJwt(exp: exp))?.timeIntervalSince1970, exp)
    }

    func testExpiryNilOnMalformedToken() {
        XCTAssertNil(SsoToken.expiry("khong-phai-jwt"))
        XCTAssertNil(SsoToken.expiry("a.b.c"))                       // payload khong base64
        XCTAssertNil(SsoToken.expiry("header.\(Data("khong-json".utf8).base64EncodedString()).sig"))
        XCTAssertNil(SsoToken.expiry(fakeJwt(exp: nil)))             // JSON hop le, thieu exp
        XCTAssertNil(SsoToken.expiry(fakeJwt(exp: nil, extra: "\"exp\":\"chuoi\"")))
    }

    func testIsUsable() {
        XCTAssertTrue(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)))
        XCTAssertFalse(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(-1).timeIntervalSince1970)))
        // Con 30 giay: qua bien do 60 giay nen coi nhu het han.
        XCTAssertFalse(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(30).timeIntervalSince1970)))
        XCTAssertTrue(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(30).timeIntervalSince1970), slack: 5))
        XCTAssertFalse(SsoToken.isUsable("rac"))
    }

    func testBase64UrlDecodeHandlesPaddingAndAlphabet() {
        // "-" va "_" phai doi thanh "+" va "/", va tu bu dau "=" con thieu.
        XCTAssertEqual(SsoToken.base64UrlDecode("YQ"), Data("a".utf8))
        XCTAssertEqual(SsoToken.base64UrlDecode("YWJj"), Data("abc".utf8))
        XCTAssertEqual(SsoToken.base64UrlDecode("-_8"), Data([0xFB, 0xFF]))
        XCTAssertNil(SsoToken.base64UrlDecode("!!!!"))
    }
}

final class KeychainTests: XCTestCase {
    override func tearDown() {
        Keychain.clear()
        super.tearDown()
    }

    func testWriteReadClear() {
        Keychain.clear()
        XCTAssertNil(Keychain.read())
        Keychain.write("token-1")
        XCTAssertEqual(Keychain.read(), "token-1")
        Keychain.write("token-2")               // ghi de, khong duplicate item
        XCTAssertEqual(Keychain.read(), "token-2")
        Keychain.clear()
        XCTAssertNil(Keychain.read())
    }
}

final class SsoCookieTests: XCTestCase {
    override func tearDown() {
        SsoCookie.remove()
        super.tearDown()
    }

    func testInstallAndRemove() {
        SsoCookie.remove()
        SsoCookie.install("abc")
        let cookie = HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" }
        XCTAssertEqual(cookie?.value, "abc")
        XCTAssertEqual(cookie?.domain, ".huyab.click")
        XCTAssertTrue(cookie?.isSecure ?? false)

        SsoCookie.remove()
        XCTAssertNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }
}

@MainActor
final class AuthStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Keychain.clear()
        SsoCookie.remove()
    }

    override func tearDown() {
        Keychain.clear()
        SsoCookie.remove()
        super.tearDown()
    }

    private var goodToken: String { fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970) }

    func testInitRestoresUsableToken() {
        Keychain.write(goodToken)
        let store = AuthStore()
        XCTAssertNotNil(store.token)
        XCTAssertNotNil(store.client)
        XCTAssertNotNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }

    func testInitDropsExpiredToken() {
        Keychain.write(fakeJwt(exp: Date().addingTimeInterval(-10).timeIntervalSince1970))
        let store = AuthStore()
        XCTAssertNil(store.token)
        XCTAssertNil(store.client)
        XCTAssertNil(Keychain.read())           // don luon cho lan sau
    }

    func testSignInSignOut() {
        let store = AuthStore()
        store.notice = "loi cu"
        store.signIn(token: goodToken)
        XCTAssertEqual(store.token, Keychain.read())
        XCTAssertNil(store.notice)

        store.signOut(notice: "het han")
        XCTAssertNil(store.token)
        XCTAssertNil(Keychain.read())
        XCTAssertEqual(store.notice, "het han")
        XCTAssertNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }

    func testPerformWithoutClientDoesNothing() async {
        let store = AuthStore()
        var ran = false
        let error = await store.perform { _ in ran = true }
        XCTAssertNil(error)
        XCTAssertFalse(ran)
    }

    func testPerformSuccessReturnsNil() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        var ran = false
        let error = await store.perform { _ in ran = true }
        XCTAssertNil(error)
        XCTAssertTrue(ran)
    }

    func testPerformUnauthorizedSignsOut() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        let error = await store.perform { _ in throw ApiError.unauthorized }
        XCTAssertNil(error)
        XCTAssertNil(store.token)
        XCTAssertEqual(store.notice, "Phiên đã hết hạn, đăng nhập lại nhé.")
    }

    func testPerformOtherErrorReturnsMessage() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        let error = await store.perform { _ in throw ApiError.status(500) }
        XCTAssertEqual(error, ApiError.status(500).localizedDescription)
        XCTAssertNotNil(store.token)            // loi thuong khong dang xuat
    }
}

final class OdooTimeTests: XCTestCase {
    /// 2025-08-12T12:00:00Z
    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    func testParseOdooTreatsNaiveStringAsUtc() {
        XCTAssertEqual(parseOdoo("2025-08-12 12:00:00"), now)
        XCTAssertEqual(parseOdoo("2025-08-12T12:00:00"), now)
        XCTAssertNil(parseOdoo("khong-phai-ngay"))
    }

    func testDelayText() {
        XCTAssertNil(delayText("2025-08-12 12:00:00", now: now))       // dung han
        XCTAssertNil(delayText("2025-08-12 13:00:00", now: now))       // chua den han
        XCTAssertEqual(delayText("2025-08-12 11:59:30", now: now), "vừa xong")
        XCTAssertEqual(delayText("2025-08-12 11:55:00", now: now), "trễ 5m")
        XCTAssertEqual(delayText("2025-08-12 11:00:00", now: now), "trễ 1h")
        XCTAssertEqual(delayText("2025-08-10 12:00:00", now: now), "trễ 2d")
        XCTAssertNil(delayText("rac", now: now))
    }

    func testIsLateUsesThreshold() {
        XCTAssertFalse(isLate("2025-08-12 11:55:00", thresholdMinutes: 30, now: now))
        XCTAssertTrue(isLate("2025-08-12 11:30:00", thresholdMinutes: 30, now: now))
        XCTAssertTrue(isLate("2025-08-12 11:55:00", thresholdMinutes: 1, now: now))
        XCTAssertFalse(isLate("rac", thresholdMinutes: 1, now: now))
    }

    func testFormatFallsBackToRawString() {
        XCTAssertEqual(formatOdooDateTime("khong-phai-ngay"), "khong-phai-ngay")
        XCTAssertTrue(formatOdooDateTime("2025-08-12 12:00:00").contains(":"))
    }

    func testEnvLabel() {
        XCTAssertEqual(envLabel("prod"), "Prod")
        XCTAssertEqual(envLabel("la"), "la")                            // kind la: hien nguyen ban
        XCTAssertEqual(envOptions.count, 3)
    }
}
