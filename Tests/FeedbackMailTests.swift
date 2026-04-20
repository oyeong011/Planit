import Foundation
import Testing
@testable import Calen

@Test func feedbackMail_encodesSubjectAndBodyQueryItems() throws {
    let url = try #require(FeedbackMail.makeURL(
        recipient: "feedback@example.com",
        version: "0.4.10",
        build: "410",
        osVersion: "macOS 15.4",
        subjectFormat: "Calen v%@ Feedback",
        bodyFormat: "\n\n---\nApp version: %@ (%@)\nmacOS: %@"
    ))

    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    let items = components.queryItems ?? []

    #expect(components.scheme == "mailto")
    #expect(components.path == "feedback@example.com")
    #expect(items.first(where: { $0.name == "subject" })?.value == "Calen v0.4.10 Feedback")
    #expect(items.first(where: { $0.name == "body" })?.value?.contains("App version: 0.4.10 (410)") == true)
    #expect(items.first(where: { $0.name == "body" })?.value?.contains("macOS: macOS 15.4") == true)
}
