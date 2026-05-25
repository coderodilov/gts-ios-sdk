import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public init(_ value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let value as JSONValue:
            self = value
        case let value as [String: Any]:
            self = .object(value.mapValues { JSONValue($0) })
        case let value as [Any]:
            self = .array(value.map { JSONValue($0) })
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .number(Double(value))
        case let value as Double:
            self = .number(value)
        case let value as Float:
            self = .number(Double(value))
        default:
            self = .string(String(describing: value!))
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return String(value)
        default:
            return nil
        }
    }

    public var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            return Bool(value)
        default:
            return nil
        }
    }

    public subscript(_ key: String) -> JSONValue? {
        objectValue?[key]
    }

    public func encodedData() throws -> Data {
        try JSONSerialization.data(withJSONObject: foundationObject(), options: [])
    }

    public func prettyPrinted() -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: foundationObject(), options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: self)
        }
        return String(data: data, encoding: .utf8) ?? String(describing: self)
    }

    public func foundationObject() -> Any {
        switch self {
        case .object(let value):
            return value.mapValues { $0.foundationObject() }
        case .array(let value):
            return value.map { $0.foundationObject() }
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        }
    }

    public static func decode(from data: Data) throws -> JSONValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return JSONValue(object)
    }

    public func findString(_ keys: String...) -> String? {
        findString(keys)
    }

    public func findString(_ keys: [String]) -> String? {
        if let direct = firstString(keys, in: self) {
            return direct
        }
        if let data = self["data"], let nested = firstString(keys, in: data) {
            return nested
        }
        return nil
    }

    public func findStringDataFirst(_ keys: String...) -> String? {
        if let data = self["data"], let nested = firstString(keys, in: data) {
            return nested
        }
        return firstString(keys, in: self)
    }

    public func findArrayDataFirst(_ keys: String...) -> [JSONValue]? {
        if let data = self["data"] {
            for key in keys {
                if let array = data[key]?.arrayValue {
                    return array
                }
            }
        }
        for key in keys {
            if let array = self[key]?.arrayValue {
                return array
            }
        }
        return nil
    }

    public func firstCurrencyCode() -> String? {
        let paths = [
            ["user", "currency_user_account", "code"],
            ["user", "currencyUserAccount", "code"],
            ["currency_user_account", "code"],
            ["currencyUserAccount", "code"],
            ["company", "currency", "code"],
            ["company_info", "currency", "code"],
            ["companyInfo", "currency", "code"]
        ]
        for path in paths {
            if let value = string(at: path), value.count == 3 {
                return value.uppercased()
            }
        }
        return recursiveCurrencyCode()?.uppercased()
    }

    public func string(at path: [String]) -> String? {
        var current: JSONValue? = self
        for key in path {
            current = current?[key]
        }
        return current?.stringValue
    }

    private func firstString(_ keys: [String], in value: JSONValue) -> String? {
        for key in keys {
            if let string = value[key]?.stringValue, !string.isEmpty {
                return string
            }
        }
        return nil
    }

    private func recursiveCurrencyCode() -> String? {
        let keys = Set(["currency_code", "currencyCode", "currency", "valyutaName"])
        switch self {
        case .object(let object):
            for key in keys {
                if let value = object[key]?.stringValue, value.range(of: #"^[A-Za-z]{3}$"#, options: .regularExpression) != nil {
                    return value
                }
            }
            for value in object.values {
                if let found = value.recursiveCurrencyCode() {
                    return found
                }
            }
        case .array(let array):
            for value in array {
                if let found = value.recursiveCurrencyCode() {
                    return found
                }
            }
        default:
            break
        }
        return nil
    }
}
