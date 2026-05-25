import Foundation

public enum GtsAuthMode: Sendable {
    case bearer
    case cookie
}

public struct GtsAuthenticatedSession: Sendable {
    public let sdk: GtsSdk
    public let bearerToken: String?
    public let cookieHeader: String?
    public let currency: String?
    public let authData: JSONValue?
}

public final class GtsSdk: @unchecked Sendable {
    public static let defaultBaseURL = "https://api2.globaltravel.space"

    public let baseURL: URL
    public let flight: FlightProduct

    private let client: GtsHttpClient

    public init(
        baseUrl: String = GtsSdk.defaultBaseURL,
        bearerToken: String? = nil,
        cookieHeader: String? = nil,
        urlSession: URLSession = .shared
    ) throws {
        guard let baseURL = URL(string: baseUrl) else {
            throw GtsSdkError.invalidBaseURL(baseUrl)
        }
        self.baseURL = baseURL
        self.client = GtsHttpClient(
            baseURL: baseURL,
            bearerToken: bearerToken,
            cookieHeader: cookieHeader,
            urlSession: urlSession
        )
        self.flight = FlightProduct(client: client)
    }

    public static func authenticate(
        email: String,
        password: String,
        baseUrl: String = GtsSdk.defaultBaseURL,
        authMode: GtsAuthMode = .bearer,
        urlSession: URLSession = .shared
    ) async throws -> GtsAuthenticatedSession {
        let authSdk = try GtsSdk(baseUrl: baseUrl, urlSession: urlSession)
        let response = try await authSdk.client.post(
            path: "v1/auth/signin/",
            body: .object([
                "email": .string(email),
                "password": .string(password)
            ])
        )

        guard response.isSuccessful else {
            throw GtsSdkError.authenticationFailed("Login failed: HTTP \(response.statusCode) \(response.compactError)")
        }

        let cookiePairs = response.extractCookiePairs(baseURL: authSdk.baseURL)
        let data = response.json?["data"]
        let bearerToken = data?.findString("token", "access_token", "jwt") ?? cookiePairs["token"]
        let cookieHeader = cookiePairs.authCookieHeader
        let fallbackCookieHeader = cookieHeader ?? bearerToken.map { "token=\($0)" }

        guard bearerToken?.isEmpty == false || cookieHeader?.isEmpty == false else {
            throw GtsSdkError.authenticationFailed("Login succeeded but no bearer token or auth cookie was returned")
        }

        let sdk: GtsSdk
        switch authMode {
        case .bearer:
            sdk = try GtsSdk(
                baseUrl: baseUrl,
                bearerToken: bearerToken,
                cookieHeader: fallbackCookieHeader,
                urlSession: urlSession
            )
        case .cookie:
            sdk = try GtsSdk(
                baseUrl: baseUrl,
                bearerToken: fallbackCookieHeader == nil ? bearerToken : nil,
                cookieHeader: fallbackCookieHeader,
                urlSession: urlSession
            )
        }

        return GtsAuthenticatedSession(
            sdk: sdk,
            bearerToken: bearerToken,
            cookieHeader: cookieHeader,
            currency: data?.firstCurrencyCode(),
            authData: data
        )
    }
}

private extension GtsResponse {
    func extractCookiePairs(baseURL: URL) -> [String: String] {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: baseURL)
        return cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var authCookieHeader: String? {
        if let esession = self["esession"], let token = self["token"], !esession.isEmpty, !token.isEmpty {
            return "esession=\(esession); token=\(token)"
        }
        let value = map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        return value.isEmpty ? nil : value
    }
}
