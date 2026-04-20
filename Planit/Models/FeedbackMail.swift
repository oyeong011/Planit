import Foundation

enum FeedbackMail {
    static func makeURL(
        recipient: String,
        version: String,
        build: String,
        osVersion: String,
        subjectFormat: String,
        bodyFormat: String
    ) -> URL? {
        let subject = String(format: subjectFormat, version)
        let body = String(format: bodyFormat, version, build, osVersion)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
