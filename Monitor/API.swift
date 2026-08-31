import Foundation

// DTO la ban chieu cua server/src/index.ts ben monitor. Server tra thang row
// cua D1 nen key la snake_case — ApiClient bat convertFromSnakeCase mot lan
// cho ca app thay vi rai CodingKeys khap noi.

struct ApiUserSettings: Decodable {
    let alertDelayMinutes: Int
}

struct ApiMe: Decodable {
    let email: String?
    let authenticated: Bool
    let settings: ApiUserSettings?
}

struct ApiConfig: Decodable, Identifiable {
    let id: Int
    let name: String
    let url: String
    let db: String
    let username: String
    let password: String
    let env: String
    /// D1 khong co bool: cot nay la INTEGER 0/1.
    let alertEnabled: Int

    var alertOn: Bool { alertEnabled != 0 }
}

/// Odoo tra many2one dang [id, name], hoac `false` khi rong.
struct OdooRef: Decodable {
    let name: String

    init(from decoder: Decoder) throws {
        guard var list = try? decoder.unkeyedContainer() else {
            name = ""
            return
        }
        _ = try? list.decode(Int.self)
        name = (try? list.decode(String.self)) ?? ""
    }
}

struct ApiCron: Decodable, Identifiable {
    let id: Int
    let name: String
    /// Gio UTC KHONG co hau to "Z" — xem parseOdoo.
    let nextcall: String
    let active: Bool
    let modelId: OdooRef?
}

struct ApiCronList: Decodable {
    let configName: String?
    let crons: [ApiCron]
}

struct ConfigInput: Encodable {
    var name: String
    var url: String
    var db: String
    var username: String
    var password: String
    var env: String
}

struct SettingsInput: Encodable {
    var alertDelayMinutes: Int

    enum CodingKeys: String, CodingKey {
        case alertDelayMinutes = "alert_delay_minutes"
    }
}

struct ReorderInput: Encodable {
    var ids: [Int]
}

enum ApiError: LocalizedError {
    /// Token het han hoac bi thu hoi — goi AuthStore.signOut, dung retry.
    case unauthorized
    case status(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Phiên đã hết hạn"
        case .status(let code): "Máy chủ trả lỗi \(code)"
        case .transport(let message): message
        }
    }
}

struct ApiClient {
    static let origin = "https://alert.huyab.click"

    let token: String
    /// Test tiem URLSession co URLProtocol gia vao day; app dung shared.
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path, method: "GET"))
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send(json(path, method: "POST", body: body))
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path, method: "POST"))
    }

    func put<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send(json(path, method: "PUT", body: body))
    }

    /// Endpoint chi doi trang thai — bo qua body tra ve.
    func fire(_ path: String, method: String) async throws {
        _ = try await send(request(path, method: method)) as Ignored
    }

    private func json(_ path: String, method: String, body: some Encodable) throws -> URLRequest {
        var req = request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: URL(string: Self.origin + path)!)
        req.httpMethod = method
        // Server doc cookie huyab_sso (AuthStore da nhet vao cookie jar); gui kem
        // Bearer cho phia nao doc header — hai duong doc lap, khong hai gi.
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// Nuot moi thu, ke ca body rong — dung cho request chi can biet 2xx.
    struct Ignored: Decodable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ApiError.unauthorized }
        guard (200..<300).contains(code) else { throw ApiError.status(code) }

        if T.self == Ignored.self { return Ignored() as! T }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            throw ApiError.transport("Không đọc được dữ liệu: \(error)")
            #else
            throw ApiError.transport("Dữ liệu trả về không đọc được")
            #endif
        }
    }
}

// MARK: - Thoi gian kieu Odoo

/// Odoo tra "2025-08-12 12:30:00" la gio UTC nhung khong co hau to. Them "Z"
/// roi parse, y nhu client/src/App.tsx lam.
func parseOdoo(_ value: String) -> Date? {
    let iso = value.replacingOccurrences(of: " ", with: "T") + "Z"
    let parsers = [ISO8601DateFormatter(), {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()]
    return parsers.lazy.compactMap { $0.date(from: iso) }.first
}

/// "19:30:00 12/08/25" theo gio may. Chuoi la tra ve nguyen ban chu khong bo
/// trong — thay chuoi la con de doan hon la thay o trong.
func formatOdooDateTime(_ value: String) -> String {
    guard let date = parseOdoo(value) else { return value }
    let out = DateFormatter()
    out.locale = Locale(identifier: "vi_VN")
    out.dateFormat = "HH:mm:ss dd/MM/yy"
    return out.string(from: date)
}

/// nil = chua den han. Con lai: "vừa xong", "trễ 5m", "trễ 2h", "trễ 3d".
func delayText(_ nextcall: String, now: Date = Date()) -> String? {
    guard let due = parseOdoo(nextcall) else { return nil }
    let seconds = now.timeIntervalSince(due)
    guard seconds > 0 else { return nil }

    let minutes = Int(seconds / 60)
    if minutes < 1 { return "vừa xong" }
    if minutes < 60 { return "trễ \(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "trễ \(hours)h" }
    return "trễ \(hours / 24)d"
}

/// Tre qua nguong canh bao cua user thi to mau do.
func isLate(_ nextcall: String, thresholdMinutes: Int, now: Date = Date()) -> Bool {
    guard let due = parseOdoo(nextcall) else { return false }
    return now.timeIntervalSince(due) >= Double(thresholdMinutes) * 60
}

// MARK: - Nhan tieng Viet

let envOptions: [(id: String, label: String)] = [
    ("dev", "Dev"),
    ("preprod", "Preprod"),
    ("prod", "Prod"),
]

func envLabel(_ id: String) -> String {
    envOptions.first { $0.id == id }?.label ?? id
}
