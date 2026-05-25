import XCTest
@testable import GtsSdk

final class GtsSdkTests: XCTestCase {
    func testJSONValueFindsAuthData() throws {
        let json = JSONValue([
            "data": [
                "token": "abc",
                "user": [
                    "currency_user_account": [
                        "code": "usd"
                    ]
                ]
            ]
        ])

        XCTAssertEqual(json["data"]?.findString("token", "access_token"), "abc")
        XCTAssertEqual(json["data"]?.firstCurrencyCode(), "USD")
    }

    func testSearchRequestShape() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var body: JSONValue?

        MockURLProtocol.handler = { request in
            XCTAssertTrue((request.url?.absoluteString ?? "").hasSuffix("/v1/content/search/"))
            body = try JSONValue.decode(from: request.httpBodyStreamData())
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"request_id":"ac622a2e-a6bc-4136-a22c-6b31859a16f0","status":"success"}"#.utf8)
            )
        }

        let sdk = try GtsSdk(
            baseUrl: "https://api2.globaltravel.space",
            bearerToken: "token",
            urlSession: urlSession
        )
        let result = try await sdk.flight.search(departure: "tas", arrival: "mow", departureDate: "2026-05-24")

        XCTAssertEqual(result.requestId, "ac622a2e-a6bc-4136-a22c-6b31859a16f0")
        XCTAssertEqual(body?["class"]?.stringValue, "E")
        XCTAssertNil(body?["property_class"])
        XCTAssertEqual(body?["chd"]?.intValue, 0, body?.prettyPrinted() ?? "missing body")
        XCTAssertEqual(body?["inf"]?.intValue, 0, body?.prettyPrinted() ?? "missing body")
        XCTAssertEqual(body?["ins"]?.intValue, 0, body?.prettyPrinted() ?? "missing body")
    }

    func testBearerBackend500RetriesWithTokenCookieFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var offersCallCount = 0

        MockURLProtocol.handler = { request in
            let urlString = request.url?.absoluteString ?? ""
            if urlString.hasSuffix("/v1/auth/signin/") {
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(#"{"data":{"token":"abc"}}"#.utf8)
                )
            }
            if urlString.hasSuffix("/v1/content/offers/") {
                offersCallCount += 1
                if offersCallCount == 1 {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
                    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
                    return (
                        HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                        Data(#"<pre class="exception_value">not enough values to unpack</pre>"#.utf8)
                    )
                }
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "token=abc")
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    Data(#"{"data":{"status":"success","offers":[]}}"#.utf8)
                )
            }
            XCTFail("Unexpected request URL: \(urlString)")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let session = try await GtsSdk.authenticate(
            email: "user@example.com",
            password: "password",
            urlSession: urlSession
        )
        let result = try await session.sdk.flight.offers(requestId: "ac622a2e-a6bc-4136-a22c-6b31859a16f0")

        XCTAssertEqual(offersCallCount, 2)
        XCTAssertEqual(result.response.authMode, "Cookie")
        XCTAssertTrue(result.response.isSuccessful)
    }

    func testPollOffersFetchesNextTokenAndAccumulatesOffers() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var requests: [JSONValue] = []
        var attemptTotals: [Int] = []

        MockURLProtocol.handler = { request in
            XCTAssertTrue((request.url?.absoluteString ?? "").hasSuffix("/v1/content/offers/"))
            let body = try JSONValue.decode(from: request.httpBodyStreamData())
            requests.append(body)

            let responseBody: String
            switch requests.count {
            case 1:
                responseBody = """
                {"data":{"status":"in process","count":3,"next_token":"token-1","offers":[{"offer_id":"offer-a","price_info":{"total_amount":"100","currency":"USD"},"routes":[]}]}}
                """
            case 2:
                responseBody = """
                {"data":{"status":"in process","count":3,"next_token":"token-2","offers":[{"offer_id":"offer-a","price_info":{"total_amount":"95","currency":"USD"},"routes":[]},{"offer_id":"offer-b","price_info":{"total_amount":"120","currency":"USD"},"routes":[]}]}}
                """
            default:
                responseBody = """
                {"data":{"status":"success","count":3,"offers":[{"offer_id":"offer-c","price_info":{"total_amount":"130","currency":"USD"},"routes":[]}]}}
                """
            }

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(responseBody.utf8)
            )
        }

        let sdk = try GtsSdk(baseUrl: "https://api2.globaltravel.space", bearerToken: "token", urlSession: urlSession)
        let result = try await sdk.flight.pollOffers(
            requestId: "request-1",
            currency: "USD",
            delayNanoseconds: 0
        ) { attempt in
            attemptTotals.append(attempt.offers.count)
        }

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0]["request_id"]?.stringValue, "request-1")
        XCTAssertEqual(requests[0]["next_token"], .null)
        XCTAssertEqual(requests[1]["next_token"]?.stringValue, "token-1")
        XCTAssertEqual(requests[2]["next_token"]?.stringValue, "token-2")
        XCTAssertEqual(attemptTotals, [1, 2, 3])
        XCTAssertEqual(result.status, "success")
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.offers.map(\.id), ["offer-a", "offer-b", "offer-c"])
        XCTAssertEqual(result.offers.first { $0.id == "offer-a" }?.price, "95")
    }

    func testFlightFacadeCoversAndroidContentEndpoints() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var requests: [(url: String, body: JSONValue)] = []

        MockURLProtocol.handler = { request in
            requests.append((
                url: request.url?.absoluteString ?? "",
                body: try JSONValue.decode(from: request.httpBodyStreamData())
            ))
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"data":{"status":"success"}}"#.utf8)
            )
        }

        let sdk = try GtsSdk(baseUrl: "https://api2.globaltravel.space", bearerToken: "token", urlSession: urlSession)
        _ = try await sdk.flight.rules(requestId: "request-1", offerId: "offer-1")
        _ = try await sdk.flight.refund(orderNumber: 3129)
        _ = try await sdk.flight.retrieve(orderNumber: 3129, requestId: "request-1", providerId: "provider-1")
        _ = try await sdk.flight.split(.object(["order_number": .number(3129)]))
        _ = try await sdk.flight.updateOrder(.object([
            "status": .string("success"),
            "order_key": .string("order-1"),
            "supplier_key": .string("supplier-1")
        ]))
        _ = try await sdk.flight.repriceCheck(orderNumber: 3129)
        _ = try await sdk.flight.repriceConfirm(orderNumber: 3129)

        XCTAssertTrue(requests[0].url.hasSuffix("/v1/content/rules/"), requests[0].url)
        XCTAssertTrue(requests[1].url.hasSuffix("/v1/content/refund/"), requests[1].url)
        XCTAssertTrue(requests[2].url.hasSuffix("/v1/content/retrieve/"), requests[2].url)
        XCTAssertTrue(requests[3].url.hasSuffix("/v1/content/split/"), requests[3].url)
        XCTAssertTrue(requests[4].url.hasSuffix("/v1/content/update-order/"), requests[4].url)
        XCTAssertTrue(requests[5].url.hasSuffix("/v1/content/reprice_check/"), requests[5].url)
        XCTAssertTrue(requests[6].url.hasSuffix("/v1/content/reprice_confirm/"), requests[6].url)
        XCTAssertEqual(requests[0].body["request_id"]?.stringValue, "request-1")
        XCTAssertEqual(requests[0].body["offer_id"]?.stringValue, "offer-1")
        XCTAssertEqual(requests[1].body["order_number"]?.intValue, 3129)
        XCTAssertEqual(requests[2].body["order_number"]?.intValue, 3129)
        XCTAssertEqual(requests[2].body["request_id"]?.stringValue, "request-1")
        XCTAssertEqual(requests[2].body["provider_id"]?.stringValue, "provider-1")
        XCTAssertEqual(requests[4].body["status"]?.stringValue, "success")
        XCTAssertEqual(requests[5].body["order_number"]?.intValue, 3129)
        XCTAssertEqual(requests[6].body["order_number"]?.intValue, 3129)
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: GtsSdkError.invalidResponse("Mock handler missing"))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func httpBodyStreamData() -> Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
