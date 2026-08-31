import XCTest
@testable import Monitor

/// Chan moi request cua URLSession rieng cua test — khong he goi mang thuc.
final class StubProtocol: URLProtocol {
    /// (status, body) tra ve, hoac loi mang. Dat truoc moi test.
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)
    nonisolated(unsafe) static var failure: Error?
    /// Request cuoi cung di qua — de kiem method/header/body.
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession doi httpBody thanh stream truoc khi den day.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ApiClientTests: XCTestCase {
    private var client: ApiClient!

    override func setUp() {
        super.setUp()
        StubProtocol.status = 200
        StubProtocol.body = Data("{}".utf8)
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
        StubProtocol.lastBody = nil

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = ApiClient(token: "tok", session: URLSession(configuration: config))
    }

    private func expectError(_ body: () async throws -> Void) async -> ApiError? {
        do {
            try await body()
            return nil
        } catch let error as ApiError {
            return error
        } catch {
            XCTFail("loi la: \(error)")
            return nil
        }
    }

    func testGetSetsBearerAndDecodesSnakeCase() async throws {
        StubProtocol.body = Data("""
        {"email":"a@b.c","authenticated":true,"settings":{"alert_delay_minutes":45}}
        """.utf8)
        let me: ApiMe = try await client.get("/api/me")
        XCTAssertEqual(me.settings?.alertDelayMinutes, 45)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString,
                       "https://alert.huyab.click/api/me")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer tok")
    }

    func testPostWithBodyEncodesJson() async throws {
        let _: ApiClient.Ignored = try await client.post("/api/configs",
            body: ConfigInput(name: "A", url: "u", db: "d", username: "n", password: "p", env: "prod"))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
        let sent = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(sent?["name"] as? String, "A")
        XCTAssertEqual(sent?["env"] as? String, "prod")
    }

    func testPostWithoutBody() async throws {
        let _: ApiClient.Ignored = try await client.post("/api/configs/1/duplicate")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"))
    }

    /// PUT /api/settings doi dung khoa snake_case, khong phai camelCase.
    func testPutSettingsUsesSnakeCaseKey() async throws {
        let _: ApiClient.Ignored = try await client.put("/api/settings",
                                                       body: SettingsInput(alertDelayMinutes: 15))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "PUT")
        let sent = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(sent?["alert_delay_minutes"] as? Int, 15)
        XCTAssertNil(sent?["alertDelayMinutes"])
    }

    func testFireIgnoresEmptyBody() async throws {
        StubProtocol.body = Data()          // body rong van phai coi la thanh cong
        try await client.fire("/api/configs/1/test-email", method: "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
    }

    func testUnauthorized() async {
        StubProtocol.status = 401
        let error = await expectError { try await self.client.fire("/api/me", method: "GET") }
        XCTAssertEqual(error?.errorDescription, ApiError.unauthorized.errorDescription)
    }

    func testNonSuccessStatus() async {
        StubProtocol.status = 500
        let error = await expectError { try await self.client.fire("/api/me", method: "GET") }
        XCTAssertEqual(error?.errorDescription, "Máy chủ trả lỗi 500")
    }

    func testTransportFailure() async {
        StubProtocol.failure = URLError(.notConnectedToInternet)
        let error = await expectError { try await self.client.fire("/api/me", method: "GET") }
        XCTAssertNotNil(error?.errorDescription)
    }

    func testDecodeFailureIsReported() async {
        StubProtocol.body = Data("[]".utf8)      // array trong khi cho object
        let error = await expectError {
            let _: ApiMe = try await self.client.get("/api/me")
        }
        XCTAssertTrue(error?.errorDescription?.contains("đọc được") ?? false, "\(error as Any)")
    }
}
