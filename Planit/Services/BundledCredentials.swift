import Foundation

// 빌드 시 CI에서 주입. 로컬 개발 시 BundledCredentials.local.swift 파일 생성.
// BundledCredentials.local.swift는 .gitignore에 포함되어 레포에 올라가지 않음.
enum BundledCredentials {
    static let clientID: String = {
        // CI 주입값 우선, 없으면 로컬 오버라이드 파일 값 사용
        if let id = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String, !id.isEmpty {
            return id
        }
        return _localClientID  // BundledCredentials.local.swift에서 정의
    }()

    static let clientSecret: String = {
        if let secret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String, !secret.isEmpty {
            return secret
        }
        return _localClientSecret
    }()
}
