import Foundation

public struct RateLimitWindowPayload: Decodable, Equatable, Sendable {
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int?
}

public struct IndividualLimitPayload: Decodable, Equatable, Sendable {
    public let remainingPercent: Int
    public let resetsAt: Int
}

public struct RateLimitSnapshotPayload: Decodable, Equatable, Sendable {
    public let limitID: String?
    public let limitName: String?
    public let primary: RateLimitWindowPayload?
    public let secondary: RateLimitWindowPayload?
    public let individualLimit: IndividualLimitPayload?
    public let spendControlReached: Bool?

    private enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case individualLimit
        case spendControlReached
    }
}

public struct RateLimitReadResult: Decodable, Equatable, Sendable {
    public let rateLimits: RateLimitSnapshotPayload?
    public let rateLimitsByLimitID: [String: RateLimitSnapshotPayload]?

    private enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
    }
}

public struct RPCErrorPayload: Decodable, Equatable, Sendable, Error {
    public let code: Int?
    public let message: String

    public init(code: Int?, message: String) {
        self.code = code
        self.message = message
    }
}

public enum AppServerIncomingMessage: Equatable, Sendable {
    case rateLimitResponse(id: Int, result: RateLimitReadResult)
    case errorResponse(id: Int?, error: RPCErrorPayload)
    case notification(method: String)
    case otherResponse(id: Int)
    case malformedRateLimitResponse(id: Int, reason: String)
    case unknown
}

public enum AppServerMessageDecoder {
    public static func decode(line: String) -> AppServerIncomingMessage {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .unknown
        }

        if let method = object["method"] as? String {
            return .notification(method: method)
        }

        let id = (object["id"] as? NSNumber)?.intValue

        if let errorObject = object["error"] as? [String: Any],
           let message = errorObject["message"] as? String {
            let error = RPCErrorPayload(
                code: (errorObject["code"] as? NSNumber)?.intValue,
                message: message
            )
            return .errorResponse(id: id, error: error)
        }

        guard let id else { return .unknown }
        guard let resultObject = object["result"] as? [String: Any] else {
            return .otherResponse(id: id)
        }

        if resultObject["rateLimits"] != nil {
            do {
                let resultData = try JSONSerialization.data(withJSONObject: resultObject)
                let result = try JSONDecoder().decode(RateLimitReadResult.self, from: resultData)
                return .rateLimitResponse(id: id, result: result)
            } catch {
                return .malformedRateLimitResponse(id: id, reason: error.localizedDescription)
            }
        }

        return .otherResponse(id: id)
    }
}
