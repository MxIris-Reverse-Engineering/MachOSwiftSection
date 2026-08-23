#if os(macOS)

import Foundation
import MachOKit
import SwiftPrinting
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
        #expect(await typeDatabase.swiftName(forCName: "TSTOptions", category: .valueType) == "Thing.Options")
        #expect(await typeDatabase.swiftName(forCName: "TSTUnknown", category: .valueType) == nil)
    }

    /// The category split end-to-end through the database: the protocol-only
    /// `NSObject` → `NSObjectProtocol` rename applies to protocol references
    /// and never to class references.
    @Test
    func nsObjectClassAndProtocolReferencesResolveSeparately() async throws {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        let apiNotesIndex = try Self.makeAPINotesIndex(yaml: """
        Name: ObjectiveC
        Classes:
        - Name: NSObject
        Protocols:
        - Name: NSObject
          SwiftName: NSObjectProtocol
        """)
        await typeDatabase.register(apiNotesIndex: apiNotesIndex)
        #expect(await typeDatabase.swiftName(forCName: "NSObject", category: .objcProtocol) == "NSObjectProtocol")
        #expect(await typeDatabase.swiftName(forCName: "NSObject", category: .objcClass) == nil)
    }

    /// `CFStringRef` is the C spelling of the natively-bridged `CFString`
    /// class (ClangImporter strips the CF `Ref` suffix), so the Swift-name
    /// lookup must translate it whenever the stripped name really exists —
    /// and must not touch a name whose stripped form is unknown.
    @Test
    func cfRefSpellingsTranslateToTheirStrippedSwiftNames() async {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(moduleEntries: [
            ModuleIndexCacheEntry(moduleName: "CoreFoundation", typeNames: ["CFString", "CFStringRef"], subModuleNames: []),
        ])
        #expect(await typeDatabase.swiftName(forCName: "CFStringRef", category: .other) == "CFString")
        #expect(await typeDatabase.swiftName(forCName: "CFStringRef", category: .objcClass) == "CFString")
        #expect(await typeDatabase.swiftName(forCName: "CFStringRef", category: .objcProtocol) == nil)
        #expect(await typeDatabase.swiftName(forCName: "SomeUnknownRef", category: .other) == nil)
        #expect(await typeDatabase.swiftName(forCName: "CFString", category: .other) == nil)
        #expect(await typeDatabase.swiftName(forCName: "Ref", category: .other) == nil)
    }

    /// An APINotes rename outranks the CF `Ref`-stripping rule for the same
    /// C name — the compiler's own record wins.
    @Test
    func apiNotesRenameOutranksTheCFRefRule() async throws {
        let typeDatabase = TypeDatabase<MachOFile>(platform: .macOS)
        await typeDatabase.register(moduleEntries: [
            ModuleIndexCacheEntry(moduleName: "TestModule", typeNames: ["TSTThing"], subModuleNames: []),
        ])
        let apiNotesIndex = try Self.makeAPINotesIndex(yaml: """
        Name: TestModule
        Typedefs:
        - Name: TSTThingRef
          SwiftName: RenamedThing
        """)
        await typeDatabase.register(apiNotesIndex: apiNotesIndex)
        #expect(await typeDatabase.swiftName(forCName: "TSTThingRef", category: .other) == "RenamedThing")
    }

    @Test
    func imagePathsReduceToModuleNames() {
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation") == "Foundation")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/swift/libswiftFoundation.dylib") == "Foundation")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/libobjc.A.dylib") == "libobjc")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/system/libsystem_c.dylib") == "libsystem_c")
    }

    /// A leading-dot last path component is a fixed point of extension
    /// stripping (`.hidden` → `.hidden`), which spun the strip loop forever
    /// before the fixed-point guard (PR #110 review, finding 5).
    @Test
    func leadingDotImagePathsTerminate() {
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/.hidden") == ".hidden")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: "/usr/lib/.x.y") == ".x")
        #expect(TypeDatabase<MachOFile>.moduleName(forImagePath: ".hidden") == ".hidden")
    }

    /// Task-group results arrive in completion order, but registration is
    /// last-writer-wins and must follow the SDK discovery order — the re-sort
    /// restores it regardless of arrival order, dropping entries discovery
    /// never named (PR #110 review, finding 7).
    @Test
    func collectedEntriesAreReorderedToDiscoveryOrder() {
        let arrivalOrderedEntries = [
            ModuleIndexCacheEntry(moduleName: "Third", typeNames: [], subModuleNames: []),
            ModuleIndexCacheEntry(moduleName: "First", typeNames: [], subModuleNames: []),
            ModuleIndexCacheEntry(moduleName: "Second", typeNames: [], subModuleNames: []),
        ]
        let orderedEntries = TypeDatabase<MachOFile>.entriesInDiscoveryOrder(
            arrivalOrderedEntries,
            discoveryOrder: ["First", "Second", "Third", "NeverIndexed"]
        )
        #expect(orderedEntries.map(\.moduleName) == ["First", "Second", "Third"])
    }
}

#endif
