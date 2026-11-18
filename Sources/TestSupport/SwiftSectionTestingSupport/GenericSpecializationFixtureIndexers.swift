@_spi(Support) import SwiftIndexing
import SwiftDeclaration
import Foundation
import Testing
import MachOKit
import MachOSwiftSection

/// The `GenericSpecializationFixture`'s prepared indexers, one per reading
/// path, each built once per process and shared by every suite: the runtime
/// one over the loaded image plus the process's `libswiftCore`, the offline
/// one over the file plus the running system's `libswiftCore` read from its
/// dyld shared cache. The standard library is there for its protocols and
/// conformances — `Hashable` is declared in it, and so is `String`'s
/// conformance to it.
package actor GenericSpecializationFixtureIndexers {
    package static let shared = GenericSpecializationFixtureIndexers()

    private var runtimeIndexer: SwiftDeclarationIndexer<MachOImage>?
    private var offlineIndexer: SwiftDeclarationIndexer<MachOFile>?

    package func runtime() async throws -> SwiftDeclarationIndexer<MachOImage> {
        if let runtimeIndexer { return runtimeIndexer }
        let indexer = SwiftDeclarationIndexer(in: try GenericSpecializationFixture.loadedImage())
        let standardLibrary = try #require(MachOImage(name: "libswiftCore"), "libswiftCore is not loaded in the test process")
        indexer.addSubIndexer(SwiftDeclarationIndexer(in: standardLibrary))
        try await indexer.prepare()
        runtimeIndexer = indexer
        return indexer
    }

    /// The fixture's definition whose own name is `name`, from `indexer`'s
    /// image — looked up by `declaredNameForTesting`, never `currentName`.
    package static func typeDefinition<MachO: MachOSwiftSectionRepresentableWithCache>(named name: String, in indexer: SwiftDeclarationIndexer<MachO>) throws -> TypeDefinition {
        try #require(
            indexer.allTypeDefinitions.values.first { $0.typeName.declaredNameForTesting == name },
            "the fixture indexer holds no definition named \(name)"
        )
    }

    package func offline() async throws -> SwiftDeclarationIndexer<MachOFile> {
        if let offlineIndexer { return offlineIndexer }
        let indexer = SwiftDeclarationIndexer(in: try GenericSpecializationFixture.machOFile())
        indexer.addSubIndexer(SwiftDeclarationIndexer(in: try GenericSpecializationFixture.systemStandardLibraryFile()))
        try await indexer.prepare()
        offlineIndexer = indexer
        return indexer
    }
}
