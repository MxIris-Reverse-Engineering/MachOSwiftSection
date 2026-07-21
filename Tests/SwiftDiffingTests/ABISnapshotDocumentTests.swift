@testable import SwiftDiffing
import Testing
import Foundation

// MARK: - Versioned persistence envelope

@Suite("ABISnapshotDocument")
struct ABISnapshotDocumentTests {
    private func sampleDocument() -> ABISnapshotDocument {
        let member = MemberRecord(
            identityKey: .mangled("$s3Foo3baryyF"),
            payloadKey: .mangled("$s3Foo3baryyF"),
            kind: .function,
            signature: "bar()"
        )
        let snapshot = ABISnapshot(
            types: [ContainerSnapshot(key: .printed("Foo"), name: "Foo", kind: .type, members: [member])],
            globalFunctions: [member]
        )
        let provenance = ABIProvenance(
            label: "1.0",
            binaryPath: "/tmp/Foo.framework/Foo",
            generatorVersion: "test",
            // A whole-second date: ISO-8601 round-trips at second precision.
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        return ABISnapshotDocument(provenance: provenance, snapshot: snapshot)
    }

    @Test("encode/decode round-trips the document")
    func roundTrip() throws {
        let document = sampleDocument()
        let decoded = try ABISnapshotDocument.decode(from: document.encoded())
        #expect(decoded == document)
    }

    @Test("encoding is byte-stable")
    func byteStableEncoding() throws {
        let document = sampleDocument()
        #expect(try document.encoded() == document.encoded())
    }

    @Test("a file without formatVersion is rejected with a typed error")
    func missingFormatVersion() throws {
        var jsonObject = try JSONSerialization.jsonObject(with: sampleDocument().encoded()) as! [String: Any]
        jsonObject.removeValue(forKey: "formatVersion")
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        #expect(throws: ABISnapshotDocumentError.missingFormatVersion) {
            try ABISnapshotDocument.decode(from: data)
        }
    }

    @Test("a foreign format version is rejected with a typed error")
    func unsupportedFormatVersion() throws {
        var jsonObject = try JSONSerialization.jsonObject(with: sampleDocument().encoded()) as! [String: Any]
        jsonObject["formatVersion"] = 999
        let data = try JSONSerialization.data(withJSONObject: jsonObject)
        #expect(throws: ABISnapshotDocumentError.unsupportedFormatVersion(
            found: 999,
            supported: ABISnapshotDocument.currentFormatVersion
        )) {
            try ABISnapshotDocument.decode(from: data)
        }
    }

    @Test("diffing two documents stamps their provenances onto the result")
    func diffCarriesProvenance() {
        let oldDocument = sampleDocument()
        var newDocument = sampleDocument()
        newDocument.provenance?.label = "2.0"
        let diff = ABIDiffer().diff(old: oldDocument, new: newDocument)
        #expect(diff.oldProvenance?.label == "1.0")
        #expect(diff.newProvenance?.label == "2.0")
        // Provenance is metadata only — identical snapshots stay an empty diff.
        #expect(diff.isEmpty)
    }
}
