import Foundation
import Testing
import MachOKit
import MachOFixtureSupport
@_spi(Support) import SwiftIndexing
import SwiftInspection
@_spi(Support) import SwiftPrivateDiscriminators

/// Private discriminators of the running system's own images, read out of its
/// dyld shared cache (evolution proposal `private-declarations`).
///
/// The discriminators and the files they are recovered to are those of
/// macOS 27.2, where they were taken; another release can move a type to
/// another file or drop it. So this suite stays out of the CI workflow's
/// filter, whose runner runs another release.
@Suite(.serialized)
struct PrivateDiscriminatorSourceFileSystemImageTests {
    /// A private class's discriminator, found through the class's own name.
    @Test func systemFoundationRecoversJSONEncoder() async throws {
        let cache = try DyldCache(path: .current)
        let foundation = try #require(cache.machOFile(named: .Foundation))
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: foundation)
        try await indexer.prepare()
        let encoder = try #require(indexer.allTypeDefinitions.keys.first { $0.name == "Foundation.__JSONEncoder" })
        let discriminator = try #require(encoder.node.privateDeclarations.first).discriminator

        // `md5 -s 'FoundationJSONEncoder.swift'`.
        #expect(discriminator == "_12768CA107A31EF2DCE034FD75B541C9")
        #expect(PrivateDiscriminatorSourceFileIndex(indexer: indexer).sourceFiles(forDiscriminators: [discriminator])[discriminator]?.fileName == "JSONEncoder.swift")
    }

    /// SwiftUICore's types print under its ABI module name, `SwiftUI`, but the
    /// compiler hashed the module's own name: only the module name taken
    /// from the image's file name recovers them. No known file names, so the
    /// file name too comes from the image's names (`EnabledKey`).
    @Test func systemSwiftUICoreHashesItsOwnModuleName() async throws {
        let cache = try DyldCache(path: .current)
        let swiftUICore = try #require(cache.machOFile(named: .SwiftUICore))
        let indexer = SwiftDeclarationIndexer(configuration: .init(), eventHandlers: [], in: swiftUICore)
        try await indexer.prepare()
        let enabledKey = try #require(indexer.allTypeDefinitions.keys.first { $0.name == "SwiftUI.EnabledKey" })
        let discriminator = try #require(enabledKey.node.privateDeclarations.first).discriminator

        // `md5 -s 'SwiftUICoreEnabled.swift'`.
        #expect(discriminator == "_09CE35833F3876FE3A3A46977D61FC64")
        #expect(PrivateDiscriminatorSourceFileIndex(indexer: indexer, knownFileNames: []).sourceFiles(forDiscriminators: [discriminator]) == [
            discriminator: .init(fileName: "Enabled.swift", moduleName: "SwiftUICore", isSynthesized: false),
        ])
    }
}
