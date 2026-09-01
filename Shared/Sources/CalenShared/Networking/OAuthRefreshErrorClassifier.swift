import Foundation

public enum OAuthRefreshClassification: Sendable, Equatable {
    case success
    case permanentRevocation
    case nonRevocationTerminal
    case retryableTransient
}

public enum OAuthRefreshErrorClassifier {
    public static func classify(
        statusCode: Int? = nil,
        body: Data = Data(),
        transportError: Error? = nil
    ) -> OAuthRefreshClassification {
        if transportError != nil {
            return .retryableTransient
        }

        guard let json = parseObject(from: body) else {
            return .retryableTransient
        }

        if let error = json["error"] as? String {
            return classifyOAuthError(error)
        }

        guard statusCode == 200 else {
            return .retryableTransient
        }

        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            return .retryableTransient
        }

        return .success
    }

    private static func parseObject(from body: Data) -> [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private static func classifyOAuthError(_ error: String) -> OAuthRefreshClassification {
        switch error {
        case "invalid_grant":
            return .permanentRevocation
        case "invalid_client",
             "unauthorized_client",
             "invalid_request",
             "unsupported_grant_type",
             "invalid_scope":
            return .nonRevocationTerminal
        default:
            return .retryableTransient
        }
    }
}
