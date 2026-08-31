import XCTest
@testable import Monitor

/// DTO la ban chieu cua server/src/index.ts. Test o day giu hai giao uoc:
/// field la KHONG lam vo decode, va field app dung phai doc dung.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try ApiClient.decoder.decode(type, from: Data(json.utf8))
    }

    func testMeAuthenticated() throws {
        let me = try decode(ApiMe.self, """
        {"email":"huy@a.vn","authenticated":true,"settings":{"alert_delay_minutes":30},
         "field_server_moi_them":1}
        """)
        XCTAssertEqual(me.email, "huy@a.vn")
        XCTAssertTrue(me.authenticated)
        XCTAssertEqual(me.settings?.alertDelayMinutes, 30)
    }

    func testMeAnonymous() throws {
        // 401 tra ve dung {"authenticated":false} — khong duoc lam vo decode.
        let me = try decode(ApiMe.self, "{\"authenticated\":false}")
        XCTAssertNil(me.email)
        XCTAssertNil(me.settings)
    }

    /// D1 tra row snake_case, va alert_enabled la INTEGER chu khong phai bool.
    func testConfigRow() throws {
        let configs = try decode([ApiConfig].self, """
        [{"id":3,"user_email":"huy@a.vn","name":"Prod chinh","url":"https://odoo.a.vn",
          "db":"prod","username":"admin","password":"secret","env":"prod",
          "alert_enabled":1,"sort_order":0,"created_at":"2025-08-12 12:00:00"},
         {"id":4,"user_email":"huy@a.vn","name":"Dev","url":"https://dev.a.vn","db":"dev",
          "username":"admin","password":"x","env":"dev","alert_enabled":0,"sort_order":1}]
        """)
        XCTAssertEqual(configs.map(\.id), [3, 4])
        XCTAssertTrue(configs[0].alertOn)
        XCTAssertFalse(configs[1].alertOn)
        XCTAssertEqual(configs[0].password, "secret")           // form sua can prefill
    }

    /// model_id la cap [id, name] cua XML-RPC, va la `false` khi Odoo bo trong.
    func testCronListHandlesOdooManyToOne() throws {
        let list = try decode(ApiCronList.self, """
        {"config_name":"Prod chinh","crons":[
          {"id":1,"name":"Gui mail","nextcall":"2025-08-12 12:00:00","active":true,
           "model_id":[41,"mail.mail"]},
          {"id":2,"name":"Khong model","nextcall":"2025-08-12 13:00:00","active":false,
           "model_id":false}]}
        """)
        XCTAssertEqual(list.configName, "Prod chinh")
        XCTAssertEqual(list.crons.first?.modelId?.name, "mail.mail")
        XCTAssertEqual(list.crons.last?.modelId?.name, "")      // false -> rong, khong vo
        XCTAssertFalse(list.crons.last?.active ?? true)
    }

    func testCronListWithoutConfigName() throws {
        let list = try decode(ApiCronList.self, "{\"crons\":[]}")
        XCTAssertNil(list.configName)
        XCTAssertTrue(list.crons.isEmpty)
    }

    func testInputsEncodeExpectedKeys() throws {
        func keys(_ value: some Encodable) throws -> [String: Any] {
            let data = try JSONEncoder().encode(value)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }

        let config = try keys(ConfigInput(name: "A", url: "u", db: "d",
                                          username: "n", password: "p", env: "preprod"))
        XCTAssertEqual(config.count, 6)
        XCTAssertEqual(config["env"] as? String, "preprod")

        XCTAssertEqual(try keys(SettingsInput(alertDelayMinutes: 45))["alert_delay_minutes"] as? Int, 45)
        XCTAssertEqual(try keys(ReorderInput(ids: [2, 1]))["ids"] as? [Int], [2, 1])
    }
}
