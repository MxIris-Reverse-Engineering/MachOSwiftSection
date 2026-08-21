#if os(macOS)

import Foundation
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
        let swiftName = index.swiftName(forCName: "TSTRenamedThing")
        #expect(swiftName?.name == "RenamedThing")
        #expect(swiftName?.moduleName == "TestModule")
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
        #expect(index.swiftName(forCName: "TSTPrivateThing") == nil)
        #expect(index.cName(forSwiftName: "__PrivateThing") == nil)
    }
}

#endif
