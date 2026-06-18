import Foundation

/// Connection details returned by the token server: where to connect and the
/// short-lived participant token to join with.
struct ConnectionDetails: Decodable {
    let serverUrl: String
    let roomName: String
    let participantToken: String
    let participantName: String?
}

enum TokenServiceError: LocalizedError {
    case missingTokenServer
    case badURL
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingTokenServer:
            return "No token server set. Run agent/token_server.py and set "
                + "AppConfig.tokenServerURL to the URL it prints."
        case .badURL:
            return "AppConfig.tokenServerURL is not a valid URL."
        case .server(let code):
            return "Token server returned HTTP \(code)."
        case .decoding:
            return "Could not read the token server response."
        }
    }
}

/// Fetches connection details from the MorseMate dev token server.
///
/// The app holds no API secret; the backend mints a short-lived token for a room
/// from its `.env` credentials. For production this becomes an authenticated
/// HTTPS service (see `Document/technical_design.md` §6.1, §8).
struct TokenService {
    func fetchConnectionDetails(
        roomName: String? = nil,
        participantName: String
    ) async throws -> ConnectionDetails {
        let base = AppConfig.tokenServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { throw TokenServiceError.missingTokenServer }
        guard let url = URL(string: base + "/token") else { throw TokenServiceError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: String] = ["participantName": participantName]
        if let roomName { payload["roomName"] = roomName }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TokenServiceError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(ConnectionDetails.self, from: data)
        } catch {
            throw TokenServiceError.decoding
        }
    }
}
