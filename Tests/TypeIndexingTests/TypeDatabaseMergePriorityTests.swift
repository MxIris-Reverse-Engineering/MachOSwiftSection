#if os(macOS)

import Foundation
import MachOKit
import Testing
@testable import TypeIndexing

/// Merge-priority behavior of `TypeDatabase`, exercised through its
/// registration steps directly — no sourcekitd, no SDK scan, no Mach-O.
@Suite
struct TypeDatabaseMergePriorityTests {
    private static func makeAPINotesIndex(yaml apiNotesYAML: String) throws -> APINotesIndex {
        let temporaryFileURL = FileManager.default.temporaryDirectory
            .appending(component: "TypeDatabaseMergePriorityTests-\(UUID().uuidString).apinotes")
        try apiNotesYAML.write(to: temporaryFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temporaryFileURL) }
        return try APINotesIndex(files: [APINotesFile(path: temporaryFileURL.path(percentEncoded: false))])
    }

    @Test
    func interfaceExtractedNamesResolve() async {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(moduleEntries: [
            ModuleIndexCacheEntry(moduleName: "Foundation", typeNames: ["NSString", "NSURLSession.Configuration"], subModuleNames: []),
            ModuleIndexCacheEntry(moduleName: "CoreGraphics", typeNames: ["CGRect"], subModuleNames: []),
        ])
        #expect(await typeDatabase.moduleName(forTypeName: "NSString") == "Foundation")
        #expect(await typeDatabase.moduleName(forTypeName: "NSURLSession.Configuration") == "Foundation")
        #expect(await typeDatabase.moduleName(forTypeName: "CGRect") == "CoreGraphics")
        #expect(await typeDatabase.moduleName(forTypeName: "UnknownType") == nil)
    }

    /// APINotes is the compiler's own attribution record, so it overrides an
    /// interface-derived entry for the same name.
    @Test
    func apiNotesAttributionOverridesInterfaceNames() async throws {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(moduleEntries: [
            ModuleIndexCacheEntry(moduleName: "WrongModule", typeNames: ["TSTThing"], subModuleNames: []),
        ])
        let apiNotesIndex = try Self.makeAPINotesIndex(yaml: """
        Name: RightModule
        Classes:
        - Name: TSTThing
          SwiftName: Thing
        """)
        await typeDatabase.register(apiNotesIndex: apiNotesIndex)
        #expect(await typeDatabase.moduleName(forTypeName: "TSTThing") == "RightModule")
    }

    @Test
    func swiftNameForCNameComesFromAPINotes() async throws {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        let apiNotesIndex = try Self.makeAPINotesIndex(yaml: """
        Name: TestModule
        Tags:
        - Name: TSTOptions
          SwiftName: Thing.Options
        """)
        await typeDatabase.register(apiNotesIndex: apiNotesIndex)
        #expect(await typeDatabase.swiftName(forCName: "TSTOptions") == "Thing.Options")
        #expect(await typeDatabase.swiftName(forCName: "TSTUnknown") == nil)
    }

    @Test
    func imagePathsReduceToModuleNames() {
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation") == "Foundation")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/swift/libswiftFoundation.dylib") == "Foundation")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/libobjc.A.dylib") == "libobjc")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/system/libsystem_c.dylib") == "libsystem_c")
    }
}

#endif
