import Testing
@testable import Calen

@Test func crudErrorNotice_userMessageNamesFailedOperation() {
    let notice = CRUDErrorNotice(operation: .delete, source: .google, eventID: "event-123")

    #expect(notice.message.contains("delete"))
    #expect(notice.message.contains("try again"))
}

@Test func crudErrorNotice_logMetadataExcludesSensitiveFields() {
    let notice = CRUDErrorNotice(operation: .update, source: .google, eventID: "event-456")
    let metadata = notice.logMetadata

    #expect(metadata["eventID"] == "event-456")
    #expect(metadata["operation"] == "update")
    #expect(metadata["source"] == "google")
    #expect(metadata["title"] == nil)
    #expect(metadata["location"] == nil)
    #expect(metadata["note"] == nil)
}
