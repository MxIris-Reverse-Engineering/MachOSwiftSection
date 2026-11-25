#if os(macOS)

import Foundation
import MachOKit
import SwiftInterface
import SwiftPrinting
import SwiftSectionFixtureSupport
import Testing
import TypeIndexing
@testable import SwiftTypeNameResolution

/// The adapters between swift-type-indexing's moved-type answers and the
/// printer (evolution proposal `moved-swift-type-modules`). Reads this Mac's
/// macOS SDK — its textual module interfaces, no sourcekitd — into a
/// temporary cache directory.
@Suite
struct TypeDatabaseMovedTypeModuleResolverTests {
    private static func indexedDatabase() async throws -> (typeDatabase: TypeDatabase, cacheDirectoryURL: URL) {
        let cacheDirectoryURL = FileManager.default.temporaryDirectory
            .appending(component: "TypeDatabaseMovedTypeModuleResolverTests-\(UUID().uuidString)")
        let typeDatabase = TypeDatabase(platform: .macOS, cacheDirectory: cacheDirectoryURL)
        try await typeDatabase.index(dependencies: [], moduleFilter: { _ in false })
        return (typeDatabase, cacheDirectoryURL)
    }

    /// A small library built against this Mac's SDK, so its `LC_BUILD_VERSION`
    /// names an SDK every move recorded in it is in effect for.
    private static func fixtureMachOFile() throws -> MachOFile {
        let libraryURL = try FixtureCompiler.shared.dynamicLibrary(
            named: "MovedTypeModuleResolverFixture",
            language: .swift,
            sourceFiles: [FixtureSourceFile(name: "MovedTypeModuleResolverFixture.swift", contents: """
            import Foundation
            public final class FixtureAnchor {}
            public struct Holder {
                public var width: CGFloat
                public init(width: CGFloat) { self.width = width }
            }
            """)],
            arguments: ["-swift-version", "5", "-target", "arm64-apple-macosx15.0"]
        )
        return try HostSlice.machOFile(at: libraryURL)
    }

    @Test
    func resolverAnswersForTheImagesSDKVersion() async throws {
        let (typeDatabase, cacheDirectoryURL) = try await Self.indexedDatabase()
        defer { try? FileManager.default.removeItem(at: cacheDirectoryURL) }
        let macOS15Resolver = TypeDatabaseMovedTypeModuleResolver(typeDatabase: typeDatabase, sdkVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
        let macOS14Resolver = TypeDatabaseMovedTypeModuleResolver(typeDatabase: typeDatabase, sdkVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0))

        #expect(await macOS15Resolver.declaringModuleName(ofMovedTypeNamed: "View", originallyDefinedIn: "SwiftUI") == "SwiftUICore")
        #expect(await macOS14Resolver.declaringModuleName(ofMovedTypeNamed: "View", originallyDefinedIn: "SwiftUI") == nil)
        #expect(await macOS14Resolver.declaringModuleName(ofMovedTypeNamed: "CGFloat", originallyDefinedIn: "CoreGraphics") == "CoreFoundation")
        #expect(await macOS15Resolver.declaringModuleName(ofMovedTypeNamed: "Int", originallyDefinedIn: "Swift") == nil)
    }

    /// Only moved types: the setup reads the SDK's interfaces as text and
    /// generates no module interface, and the `__C` questions are not
    /// answered.
    @Test
    func providerWithOnlyMovedTypesAnswersNoCImportedQuestion() async throws {
        let machOFile = try Self.fixtureMachOFile()
        let provider = try #require(SwiftInterfaceBuilderTypeNameProvider(
            machO: machOFile,
            dependencies: SwiftInterfaceBuilderDependencies(machO: machOFile, searchPaths: []),
            resolutions: .movedTypeModules
        ))
        try await provider.setup()
        #expect(await provider.declaringModuleName(ofMovedTypeNamed: "CGFloat", originallyDefinedIn: "CoreGraphics") == "CoreFoundation")
        #expect(await provider.moduleName(forTypeName: "NSObject") == nil)
        #expect(await provider.swiftName(forCName: "CFStringRef", category: .other) == nil)
    }

    /// The default keeps what the provider resolved before moved types
    /// existed; it is not asked about moves, so nothing is indexed here.
    @Test
    func providerDefaultKeepsTodaysResolutions() async throws {
        let machOFile = try Self.fixtureMachOFile()
        let provider = try #require(SwiftInterfaceBuilderTypeNameProvider(
            machO: machOFile,
            dependencies: SwiftInterfaceBuilderDependencies(machO: machOFile, searchPaths: [])
        ))
        #expect(provider.resolutions == .cImportedModules)
        #expect(await provider.declaringModuleName(ofMovedTypeNamed: "CGFloat", originallyDefinedIn: "CoreGraphics") == nil)
    }
}

#endif
