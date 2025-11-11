import Foundation

enum APIError: Error {
    case invalidURL
    case requestFailed(Int)
    case decoding
}

protocol HTTPClient {
    func send<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        method: String,
        headers: [String: String],
        body: RequestBody?
    ) async throws -> ResponseBody
}

struct DefaultHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: RequestBody? = nil
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(-1)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            // Log error response for debugging
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ HTTP Error \(httpResponse.statusCode): \(errorBody)")
            }
            throw APIError.requestFailed(httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Decoding error. Response body: \(jsonString)")
            }
            throw APIError.decoding
        }
    }
}


