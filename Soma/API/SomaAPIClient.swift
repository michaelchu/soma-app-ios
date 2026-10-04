import Foundation

// MARK: - Soma REST API client
//
// Talks to the Soma Vercel serverless API (api/blood-pressure.ts etc.) over HTTPS.
// The API requires a bearer token (see ../../soma-api-auth/README.md for the
// server-side setup). The token lives in the Keychain; the base URL in UserDefaults.

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case requestFailed(Int, String)
    case decodingFailed
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "API URL or token is not configured. Open Settings to set it up."
        case .unauthorized: return "The API rejected the token (401). Check the token in Settings."
        case .requestFailed(let code, let msg): return "Request failed (\(code)): \(msg)"
        case .decodingFailed: return "Could not understand the server response."
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

final class SomaAPIClient {
    static let shared = SomaAPIClient()
    private init() {}

    private let baseURLKey = "soma.apiBaseURL"

    var baseURLString: String {
        get { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: baseURLKey) }
    }

    var isConfigured: Bool {
        !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(KeychainHelper.loadToken()?.isEmpty ?? true)
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        let base = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, let token = KeychainHelper.loadToken(), !token.isEmpty,
              let url = URL(string: base + path) else {
            throw APIError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = body
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.decodingFailed }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw APIError.unauthorized }
            let msg = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error ?? "Unknown error"
            throw APIError.requestFailed(http.statusCode, msg)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    // MARK: - Blood pressure endpoints (mirror api/blood-pressure.ts)

    struct RowsResponse: Decodable { let rows: [BPReadingRow] }
    struct CreateResponse: Decodable { let sessionId: String; let rows: [BPReadingRow] }

    /// GET /api/blood-pressure -> all rows, newest first
    func fetchBloodPressureRows() async throws -> [BPReadingRow] {
        let req = try makeRequest(path: "/api/blood-pressure", method: "GET")
        return try await send(req, as: RowsResponse.self).rows
    }

    struct NewReading: Encodable {
        let systolic: Int
        let diastolic: Int
        let pulse: Int?
        let arm: Arm?
    }
    struct CreatePayload: Encodable {
        let session: SessionPayload
        let notes: String?
        struct SessionPayload: Encodable {
            let date: String
            let timeOfDay: TimeOfDay
            let readings: [NewReading]
        }
    }

    /// POST /api/blood-pressure -> creates a session
    @discardableResult
    func createSession(date: String, timeOfDay: TimeOfDay, readings: [NewReading], notes: String?) async throws -> String {
        let payload = CreatePayload(
            session: .init(date: date, timeOfDay: timeOfDay, readings: readings),
            notes: notes
        )
        let body = try JSONEncoder().encode(payload)
        let req = try makeRequest(path: "/api/blood-pressure", method: "POST", body: body)
        return try await send(req, as: CreateResponse.self).sessionId
    }

    /// DELETE /api/blood-pressure?sessionId=...
    func deleteSession(sessionId: String) async throws {
        let encoded = sessionId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionId
        let req = try makeRequest(path: "/api/blood-pressure?sessionId=\(encoded)", method: "DELETE")
        struct Ok: Decodable { let ok: Bool? }
        _ = try await send(req, as: Ok.self)
    }
}

private struct APIErrorBody: Decodable {
    let error: String?
}
