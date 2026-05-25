import Foundation

final class GtsHttpClient: @unchecked Sendable {
    enum AuthMode {
        case bearer
        case cookie
        case none
    }

    private let baseURL: URL
    private let bearerToken: String?
    private let cookieHeader: String?
    private let urlSession: URLSession

    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"

    init(baseURL: URL, bearerToken: String?, cookieHeader: String?, urlSession: URLSession) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken?.nilIfBlank
        self.cookieHeader = cookieHeader?.nilIfBlank
        self.urlSession = urlSession
    }

    func get(path: String, queryItems: [URLQueryItem] = []) async throws -> GtsResponse {
        try await send(method: "GET", path: path, queryItems: queryItems, body: nil)
    }

    func post(path: String, body: JSONValue) async throws -> GtsResponse {
        try await send(method: "POST", path: path, queryItems: [], body: try body.encodedData())
    }

    private func send(method: String, path: String, queryItems: [URLQueryItem], body: Data?) async throws -> GtsResponse {
        let firstMode = preferredAuthMode()
        let first = try await perform(method: method, path: path, queryItems: queryItems, body: body, authMode: firstMode)
        if firstMode == .bearer, cookieHeader != nil, first.shouldRetryWithCookieToken {
            return try await perform(method: method, path: path, queryItems: queryItems, body: body, authMode: .cookie)
        }
        return first
    }

    private func preferredAuthMode() -> AuthMode {
        if bearerToken != nil { return .bearer }
        if cookieHeader != nil { return .cookie }
        return .none
    }

    private func perform(method: String, path: String, queryItems: [URLQueryItem], body: Data?, authMode: AuthMode) async throws -> GtsResponse {
        var request = URLRequest(url: try makeURL(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.httpBody = body
        request.httpShouldHandleCookies = false
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("en,en-US;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://test.globaltravel.space", forHTTPHeaderField: "Origin")
        request.setValue("https://test.globaltravel.space/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        switch authMode {
        case .bearer:
            if let bearerToken {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            }
        case .cookie:
            if let cookieHeader {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
        case .none:
            break
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GtsSdkError.invalidResponse("Expected HTTPURLResponse")
        }
        return GtsResponse(
            statusCode: http.statusCode,
            headers: http.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            },
            data: data,
            json: try? JSONValue.decode(from: data),
            authMode: authMode.description
        )
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GtsSdkError.invalidURL(path)
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, cleanPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let result = components.url else {
            throw GtsSdkError.invalidURL(path)
        }
        return result
    }
}

private extension GtsResponse {
    var shouldRetryWithCookieToken: Bool {
        statusCode == 401 ||
            (statusCode >= 500 && compactError.localizedCaseInsensitiveContains("not enough values to unpack"))
    }
}

private extension GtsHttpClient.AuthMode {
    var description: String {
        switch self {
        case .bearer:
            return "Bearer"
        case .cookie:
            return "Cookie"
        case .none:
            return "None"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
