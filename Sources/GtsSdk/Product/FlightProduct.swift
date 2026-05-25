import Foundation

public struct FlightSearchResult: Sendable {
    public let response: GtsResponse
    public let requestId: String?
    public let status: String?
}

public struct FlightOffersResult: Sendable {
    public let response: GtsResponse
    public let status: String?
    public let count: Int?
    public let nextToken: String?
    public let message: String?
    public let offers: [FlightOfferSummary]

    public var isInProcess: Bool {
        status?.localizedCaseInsensitiveCompare("in process") == .orderedSame
    }
}

public struct FlightUpsellResult: Sendable {
    public let response: GtsResponse
    public let status: String?
    public let message: String?
    public let offers: [FlightOfferSummary]
}

public struct FlightOfferSummary: Identifiable, Sendable {
    public let id: String
    public let route: String
    public let price: String?
    public let currency: String?
    public let provider: String?
    public let booking: String?
    public let upsell: String?
}

public struct FlightOrderSummary: Identifiable, Sendable {
    public let id: String
    public let route: String
    public let status: String?
    public let price: String?
    public let currency: String?
    public let gdsPnr: String?
    public let provider: String?
}

public final class FlightProduct: @unchecked Sendable {
    private let client: GtsHttpClient

    init(client: GtsHttpClient) {
        self.client = client
    }

    public func search(_ request: JSONValue) async throws -> GtsResponse {
        try await client.post(path: "v1/content/search/", body: request)
    }

    public func search(
        departure: String,
        arrival: String,
        departureDate: String,
        adults: Int = 1,
        propertyClass: String = "E",
        flexible: Bool = false,
        direct: Bool = false,
        airlines: [String] = []
    ) async throws -> FlightSearchResult {
        let request = JSONValue.object([
            "directions": .array([
                .object([
                    "departure": .string(departure.uppercased()),
                    "arrival": .string(arrival.uppercased()),
                    "departure_date": .string(departureDate)
                ])
            ]),
            "adt": .number(Double(adults)),
            "chd": .number(0),
            "inf": .number(0),
            "ins": .number(0),
            "class": .string(propertyClass),
            "flexible": .bool(flexible),
            "direct": .bool(direct),
            "airlines": .array(airlines.map { .string($0) })
        ])
        let response = try await search(request)
        return FlightSearchResult(
            response: response,
            requestId: response.json?.findString("request_id", "requestId"),
            status: response.json?.findString("status")
        )
    }

    public func offers(_ request: JSONValue) async throws -> GtsResponse {
        try await client.post(path: "v1/content/offers/", body: request)
    }

    public func offers(requestId: String, nextToken: String? = nil, currency: String = "USD") async throws -> FlightOffersResult {
        let request = JSONValue.object([
            "request_id": .string(requestId),
            "next_token": nextToken.map(JSONValue.string) ?? .null,
            "sort_type": .string("price"),
            "currency": .string(currency)
        ])
        let response = try await offers(request)
        return FlightOffersResult(
            response: response,
            status: response.json?.findStringDataFirst("status"),
            count: response.json?.findStringDataFirst("count").flatMap(Int.init) ?? response.json?["data"]?["count"]?.intValue,
            nextToken: response.json?.findStringDataFirst("next_token", "nextToken"),
            message: response.json?.findStringDataFirst("message"),
            offers: response.json?.findArrayDataFirst("offers")?.mapOffers() ?? []
        )
    }

    public func pollOffers(
        requestId: String,
        currency: String = "USD",
        maxAttempts: Int = 60,
        delayNanoseconds: UInt64 = 2_000_000_000,
        onAttempt: ((FlightOffersResult) -> Void)? = nil
    ) async throws -> FlightOffersResult {
        var nextToken: String?
        var latest: FlightOffersResult?
        var collectedOffers: [FlightOfferSummary] = []
        for _ in 1...maxAttempts {
            let result = try await offers(requestId: requestId, nextToken: nextToken, currency: currency)
            collectedOffers.merge(result.offers)
            let cumulativeResult = result.withOffers(collectedOffers)
            latest = cumulativeResult
            onAttempt?(cumulativeResult)
            if !cumulativeResult.response.isSuccessful || !cumulativeResult.isInProcess {
                return cumulativeResult
            }
            nextToken = cumulativeResult.nextToken
            if nextToken?.isEmpty != false {
                return cumulativeResult
            }
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let latest else {
            throw GtsSdkError.invalidResponse("Offers polling did not start")
        }
        return latest
    }

    public func verify(requestId: String, offerId: String) async throws -> GtsResponse {
        try await client.post(path: "v1/content/verify/", body: requestIdOfferBody(requestId: requestId, offerId: offerId))
    }

    public func upsell(requestId: String, offerId: String) async throws -> GtsResponse {
        try await client.post(path: "v1/content/upsell/", body: requestIdOfferBody(requestId: requestId, offerId: offerId))
    }

    public func upsellOffers(requestId: String, offerId: String) async throws -> FlightUpsellResult {
        let response = try await upsell(requestId: requestId, offerId: offerId)
        return FlightUpsellResult(
            response: response,
            status: response.json?.findStringDataFirst("status"),
            message: response.json?.findStringDataFirst("message"),
            offers: response.json?.findArrayDataFirst("offers")?.mapOffers() ?? []
        )
    }

    public func rules(requestId: String, offerId: String) async throws -> GtsResponse {
        try await client.post(path: "v1/content/rules/", body: requestIdOfferBody(requestId: requestId, offerId: offerId))
    }

    public func booking(_ request: JSONValue) async throws -> GtsResponse {
        try await client.post(path: "v1/content/booking/", body: request)
    }

    public func cancel(orderNumber: Int) async throws -> GtsResponse {
        try await client.post(path: "v1/content/cancel/", body: .object(["order_number": .number(Double(orderNumber))]))
    }

    public func ticketing(orderNumber: Int, paymentMethod: String = "deposit") async throws -> GtsResponse {
        try await client.post(
            path: "v1/content/ticketing/",
            body: .object([
                "order_number": .number(Double(orderNumber)),
                "payment_method": .string(paymentMethod)
            ])
        )
    }

    public func void(orderNumber: Int) async throws -> GtsResponse {
        try await client.post(path: "v1/content/void/", body: .object(["order_number": .number(Double(orderNumber))]))
    }

    public func refund(orderNumber: Int) async throws -> GtsResponse {
        try await client.post(path: "v1/content/refund/", body: .object(["order_number": .number(Double(orderNumber))]))
    }

    public func retrieve(orderNumber: Int, requestId: String? = nil, providerId: String? = nil) async throws -> GtsResponse {
        try await client.post(
            path: "v1/content/retrieve/",
            body: objectBody([
                "order_number": .number(Double(orderNumber)),
                "request_id": requestId.map(JSONValue.string),
                "provider_id": providerId.map(JSONValue.string)
            ])
        )
    }

    public func split(_ request: JSONValue) async throws -> GtsResponse {
        try await client.post(path: "v1/content/split/", body: request)
    }

    public func updateOrder(_ request: JSONValue) async throws -> GtsResponse {
        try await client.post(path: "v1/content/update-order/", body: request)
    }

    public func repriceCheck(orderNumber: Int) async throws -> GtsResponse {
        try await client.post(path: "v1/content/reprice_check/", body: .object(["order_number": .number(Double(orderNumber))]))
    }

    public func repriceConfirm(orderNumber: Int) async throws -> GtsResponse {
        try await client.post(path: "v1/content/reprice_confirm/", body: .object(["order_number": .number(Double(orderNumber))]))
    }

    public func orders(page: Int = 1, perPage: Int = 20) async throws -> GtsResponse {
        try await orderList(path: "v1/orders/list/", page: page, perPage: perPage)
    }

    public func agentOrders(page: Int = 1, perPage: Int = 20) async throws -> GtsResponse {
        try await orderList(path: "v1/orders/list/agreement/", page: page, perPage: perPage)
    }

    public func orderSummaries(page: Int = 1, perPage: Int = 20) async throws -> [FlightOrderSummary] {
        let response = try await orders(page: page, perPage: perPage)
        guard response.isSuccessful else {
            throw GtsSdkError.httpError(statusCode: response.statusCode, body: response.compactError)
        }
        return response.json?.findArrayDataFirst("orders")?.mapOrders() ?? []
    }

    public func agentOrderSummaries(page: Int = 1, perPage: Int = 20) async throws -> [FlightOrderSummary] {
        let response = try await agentOrders(page: page, perPage: perPage)
        guard response.isSuccessful else {
            throw GtsSdkError.httpError(statusCode: response.statusCode, body: response.compactError)
        }
        return response.json?.findArrayDataFirst("orders")?.mapOrders() ?? []
    }

    public func orderDetails(orderNumber: String) async throws -> GtsResponse {
        try await client.get(path: "v1/orders/\(orderNumber)")
    }

    public func agentOrderDetails(orderNumber: String) async throws -> GtsResponse {
        try await client.get(path: "v1/orders/\(orderNumber)/agreement")
    }

    private func orderList(path: String, page: Int, perPage: Int) async throws -> GtsResponse {
        try await client.get(
            path: path,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
        )
    }

    private func requestIdOfferBody(requestId: String, offerId: String) -> JSONValue {
        .object([
            "request_id": .string(requestId),
            "offer_id": .string(offerId)
        ])
    }

    private func objectBody(_ fields: [String: JSONValue?]) -> JSONValue {
        .object(fields.compactMapValues { $0 })
    }
}

private extension FlightOffersResult {
    func withOffers(_ offers: [FlightOfferSummary]) -> FlightOffersResult {
        FlightOffersResult(
            response: response,
            status: status,
            count: count,
            nextToken: nextToken,
            message: message,
            offers: offers
        )
    }
}

private extension Array where Element == FlightOfferSummary {
    mutating func merge(_ newOffers: [FlightOfferSummary]) {
        for offer in newOffers {
            if let index = firstIndex(where: { $0.id == offer.id }) {
                self[index] = offer
            } else {
                append(offer)
            }
        }
    }
}

private extension Array where Element == JSONValue {
    func mapOffers() -> [FlightOfferSummary] {
        enumerated().compactMap { index, item in
            guard let object = item.objectValue else { return nil }
            let priceInfo = object["price_info"]?.objectValue ?? object["priceInfo"]?.objectValue
            let firstPriceDetails = (object["price_details"]?.arrayValue ?? object["priceDetails"]?.arrayValue)?
                .first?
                .objectValue
            let routes = object["routes"]?.arrayValue
            return FlightOfferSummary(
                id: object.firstString("offer_id", "offerId", "id") ?? "#\(index + 1)",
                route: routes?.routeText() ?? "routes=\(routes?.count ?? 0)",
                price: priceInfo?.firstString("total_amount", "totalAmount", "total", "price", "amount")
                    ?? firstPriceDetails?.firstString("total_amount", "totalAmount", "total", "price", "amount"),
                currency: priceInfo?.firstString("currency")
                    ?? firstPriceDetails?.firstString("currency")
                    ?? object.firstString("currency"),
                provider: object["provider"]?.objectValue?.firstString("name", "code", "title")
                    ?? object.firstString("provider"),
                booking: object["booking"]?.stringValue,
                upsell: object["upsell"]?.stringValue
            )
        }
    }

    func mapOrders() -> [FlightOrderSummary] {
        enumerated().compactMap { index, item in
            guard let object = item.objectValue else { return nil }
            let priceInfo = object["price_info"]?.objectValue ?? object["priceInfo"]?.objectValue
            let routes = object["routes"]?.arrayValue
            return FlightOrderSummary(
                id: object.firstString("order_number", "orderNumber", "id") ?? "#\(index + 1)",
                route: routes?.routeText() ?? "routes=\(routes?.count ?? 0)",
                status: object.firstString("status"),
                price: priceInfo?.firstString("total_amount", "totalAmount", "total", "price", "amount"),
                currency: priceInfo?.firstString("currency") ?? object.firstString("currency"),
                gdsPnr: object.firstString("gds_pnr", "gdsPnr"),
                provider: object["provider"]?.objectValue?.firstString("name", "code", "title") ?? object.firstString("provider")
            )
        }
    }

    func routeText() -> String {
        let parts = compactMap { route -> String? in
            guard let object = route.objectValue else { return nil }
            let from = object.findCode("departure", "from", "origin", "departure_airport", "departureAirport")
            let to = object.findCode("arrival", "to", "destination", "arrival_airport", "arrivalAirport")
            guard let from, let to else { return nil }
            return "\(from)-\(to)"
        }
        return parts.isEmpty ? "routes=\(count)" : parts.joined(separator: ", ")
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func firstString(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func findCode(_ keys: String...) -> String? {
        for key in keys {
            if let direct = self[key]?.stringValue, !direct.isEmpty, direct.count <= 4 {
                return direct
            }
            if let nested = self[key]?.objectValue?.firstString("code", "iata", "iata_code", "iataCode"), !nested.isEmpty {
                return nested
            }
        }
        return nil
    }
}
