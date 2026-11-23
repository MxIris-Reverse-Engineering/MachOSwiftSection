#if os(macOS)

import Foundation
import MachOKit
import SwiftPrinting
import Testing
import TypeIndexing
@testable import SwiftTypeNameResolution

/// The adapter between swift-type-indexing's `TypeDatabase` and the printer's
/// type-name resolver roles.
@Suite
struct TypeDatabaseTypeNameResolverTests {
    @Test
    func resolverMapsEveryPrinterCategory() {
        #expect(ImportedTypeNameCategory(CImportedTypeNameCategory.objcClass) == .objcClass)
        #expect(ImportedTypeNameCategory(CImportedTypeNameCategory.objcProtocol) == .objcProtocol)
        #expect(ImportedTypeNameCategory(CImportedTypeNameCategory.valueType) == .valueType)
        #expect(ImportedTypeNameCategory(CImportedTypeNameCategory.other) == .other)
    }

    /// A Mac Catalyst binary reads the macOS SDK through `System/iOSSupport`:
    /// mapped to `.macOS`, as before the index moved out, its UIKit types
    /// found no API notes.
    @Test
    func buildPlatformsMapToTheirSDKs() {
        #expect(SDKPlatform(MachOKit.Platform.macOS) == .macOS)
        #expect(SDKPlatform(MachOKit.Platform.macCatalyst) == .macCatalyst)
        #expect(SDKPlatform(MachOKit.Platform.iOS) == .iOS)
        #expect(SDKPlatform(MachOKit.Platform.iOSSimulator) == .iOSSimulator)
    }

    /// The printer's two questions, answered from API notes: the declaring
    /// module, and the Swift name of a `SwiftPrivate` class and of a
    /// protocol-only rename. Reads this Mac's macOS SDK (API notes only, no
    /// sourcekitd) plus a supplementary file.
    @Test
    func resolverAnswersModuleAndSwiftName() async throws {
        guard #available(macOS 13.0, *) else { return }
        let temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appending(component: "TypeDatabaseTypeNameResolverTests-\(UUID().uuidString)")
        let apiNotesDirectoryURL = temporaryDirectoryURL.appending(component: "APINotes")
        try FileManager.default.createDirectory(at: apiNotesDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectoryURL) }
        try """
        Name: SampleKit
        Classes:
        - Name: SMPHiddenState
          SwiftPrivate: true
        Protocols:
        - Name: SMPDelegate
          SwiftName: SampleDelegate
        """.write(to: apiNotesDirectoryURL.appending(component: "SampleKit.apinotes"), atomically: true, encoding: .utf8)

        let typeDatabase = TypeDatabase(
            platform: .macOS,
            cacheDirectory: temporaryDirectoryURL.appending(component: "Cache"),
            supplementaryAPINotesURLs: [apiNotesDirectoryURL]
        )
        try await typeDatabase.index(dependencies: [], moduleFilter: { _ in false })
        let resolver = TypeDatabaseTypeNameResolver(typeDatabase: typeDatabase)

        #expect(await resolver.moduleName(forTypeName: "SMPHiddenState") == "SampleKit")
        #expect(await resolver.swiftName(forCName: "SMPHiddenState", category: .objcClass) == "__SMPHiddenState")
        #expect(await resolver.swiftName(forCName: "SMPDelegate", category: .objcProtocol) == "SampleDelegate")
        #expect(await resolver.swiftName(forCName: "SMPDelegate", category: .objcClass) == nil)
        #expect(await resolver.moduleName(forTypeName: "NSObject") == "ObjectiveC")
    }
}

#endif
