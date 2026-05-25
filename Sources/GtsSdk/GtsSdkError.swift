import Foundation

public enum GtsSdkError: Error, LocalizedError, Sendable {
    case invalidBaseURL(String)
    case invalidURL(String)
    case invalidRequest(String)
    case authenticationFailed(String)
    case missingAuthentication
    case httpError(statusCode: Int, body: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid base URL: \(value)"
        case .invalidURL(let value):
            return "Invalid URL: \(value)"
        case .invalidRequest(let value):
            return value
        case .authenticationFailed(let value):
            return value
        case .missingAuthentication:
            return "No bearer token or cookie header is configured"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode) \(body)"
        case .invalidResponse(let value):
            return value
        }
    }
}
