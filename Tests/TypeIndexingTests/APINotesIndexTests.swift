#if os(macOS)

import Foundation
import SwiftPrinting
import Testing
@testable import TypeIndexing

@Suite
struct APINotesIndexTests {
    /// Writes a minimal APINotes YAML to a temporary file and parses it the
    /// same way SDK discovery does.
    private static func makeIndex() throws -> APINotesIndex {
        let apiNotesYAML = """
        Name: TestModule
        Classes:
        - Name: TSTRenamedThing
          SwiftName: RenamedThing
        - Name: TSTPlainThing
        - Name: TSTPrivateThing
          SwiftName: __PrivateThing
          SwiftPrivate: true
        Tags:
        - Name: TSTOptions
          SwiftName: RenamedThing.Options
        Typedefs:
        - Name: TSTIdentifier
        """
        let temporaryFileURL = FileManager.default.temporaryDirectory
            .appending(component: "APINotesIndexTests-\(UUID().uuidString).apinotes")
        try apiNotesYAML.write(to: temporaryFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryFileURL) }
        let apiNotesFile = try APINotesFile(path: temporaryFileURL.path(percentEncoded: false))
        return APINotesIndex(files: [apiNotesFile])
    }

    /// The historical implementation stored the *Swift name* into the
    /// `moduleName` field of the C-name → Swift-name mapping, so the declaring
    /// module was unrecoverable. The declaring module must be the module whose
    /// APINotes file carries the entry.
    @Test
    func swiftNameLookupCarriesTheDeclaringModule() throws {
        let index = try Self.makeIndex()
        let swiftName = index.swiftName(forCName: "TSTRenamedThing", category: .objcClass)
        #expect(swiftName?.name == "RenamedThing")
        #expect(swiftName?.moduleName == "TestModule")
    }

    /// ObjC declares both a class and a protocol named `NSObject`, and only
    /// the protocol is renamed — the tables must be category-isolated so the
    /// protocol's rename never rewrites class references.
    @Test
    func renameTablesAreCategoryIsolated() throws {
        let apiNotesYAML = """
        Name: ObjectiveC
        Classes:
        - Name: NSObject
        Protocols:
        - Name: NSObject
          SwiftName: NSObjectProtocol
        """
        let temporaryFileURL = FileManager.default.temporaryDirectory
            .appending(component: "APINotesIndexTests-\(UUID().uuidString).apinotes")
        try apiNotesYAML.write(to: temporaryFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryFileURL) }
        let index = try APINotesIndex(files: [APINotesFile(path: temporaryFileURL.path(percentEncoded: false))])

        #expect(index.swiftName(forCName: "NSObject", category: .objcProtocol)?.name == "NSObjectProtocol")
        #expect(index.swiftName(forCName: "NSObject", category: .objcClass) == nil)
        #expect(index.swiftName(forCName: "NSObject", category: .other) == nil)
    }

    @Test
    func cNameLookupIsTheReverseDirection() throws {
        let index = try Self.makeIndex()
        let cName = index.cName(forSwiftName: "RenamedThing.Options")
        #expect(cName?.name == "TSTOptions")
        #expect(cName?.moduleName == "TestModule")
    }

    @Test
    func everyListedEntityGetsModuleAttributionRenamedOrNot() throws {
        let index = try Self.makeIndex()
        #expect(index.moduleName(forCName: "TSTRenamedThing") == "TestModule")
        #expect(index.moduleName(forCName: "TSTPlainThing") == "TestModule")
        #expect(index.moduleName(forCName: "TSTOptions") == "TestModule")
        #expect(index.moduleName(forCName: "TSTIdentifier") == "TestModule")
        #expect(index.moduleName(forCName: "TSTUnknown") == nil)
    }

    /// `SwiftPrivate` entities keep their module attribution (their C name
    /// still appears in manglings) but stay out of the rename tables.
    @Test
    func swiftPrivateEntitiesAreAttributedButNotRenamed() throws {
        let index = try Self.makeIndex()
        #expect(index.moduleName(forCName: "TSTPrivateThing") == "TestModule")
        #expect(index.swiftName(forCName: "TSTPrivateThing", category: .objcClass) == nil)
        #expect(index.cName(forSwiftName: "__PrivateThing") == nil)
    }
}

#endif
