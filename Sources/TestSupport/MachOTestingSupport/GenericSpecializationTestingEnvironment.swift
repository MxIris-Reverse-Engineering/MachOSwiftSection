@_spi(Support) import SwiftSpecialization
@_spi(Support) import SwiftDeclaration
@_spi(Support) import SwiftIndexing
import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
import MachOSwiftSection
@_spi(Support) import SwiftInterface

// MARK: - Process-wide caches

/// Shared per-process `MachOImage.current()` reference.
///
/// `MachOImage.current()` is documented to return the same identity on every
/// call, so caching here just spares the function-call overhead and gives
/// callers a stable property to read.
private let _sharedMachO: MachOImage = .current()

/// One-shot cache of a fully-prepared `SwiftDeclarationIndexer` over the
/// current image plus Foundation and libswiftCore.
///
/// swift-testing instantiates a fresh suite struct per `@Test`; the actor
/// lets every conforming suite share a single prepared indexer instead of
/// paying the preparation cost N × suite-count times.
private actor SharedSpecializationIndexerCache {
    static let shared = SharedSpecializationIndexerCache()

    private var indexerCache: SwiftDeclarationIndexer<MachOImage>?

    enum CacheError: Error, LocalizedError {
        case missingImage(name: String)

        var errorDescription: String? {
            switch self {
            case .missingImage(let name):
                return "expected MachOImage(name: \"\(name)\") to be loadable for the test fixture"
            }
        }
    }

    func indexer() async throws -> SwiftDeclarationIndexer<MachOImage> {
        if let indexerCache { return indexerCache }
        let indexer = SwiftDeclarationIndexer(in: MachOImage.current())
        try indexer.addSubIndexer(SwiftDeclarationIndexer(in: Self.requireImage(name: "Foundation")))
        try indexer.addSubIndexer(SwiftDeclarationIndexer(in: Self.requireImage(name: "libswiftCore")))
        try await indexer.prepare()
        indexerCache = indexer
        return indexer
    }

    private static func requireImage(name: String) throws -> MachOImage {
        guard let image = MachOImage(name: name) else {
            throw CacheError.missingImage(name: name)
        }
        return image
    }
}

// MARK: - Protocol

/// Shared environment for swift-testing suites that drive end-to-end
/// generic-specialization machinery: each conforming suite gets a sync
/// `machO` and an async `indexer` for free, plus descriptor-lookup helpers,
/// all backed by a single per-process cache.
///
/// Lives in `MachOTestingSupport` so any test target depending on it can
/// adopt the protocol without copy-pasting the boilerplate or reaching into
/// another test file's nested namespace.
package protocol GenericSpecializationTestingEnvironment {
    var machO: MachOImage { get }
    var indexer: SwiftDeclarationIndexer<MachOImage> { get async throws }
}

// MARK: - Default implementations

extension GenericSpecializationTestingEnvironment {
    /// Sync access to the cached `MachOImage.current()` — every conforming
    /// suite shares the same instance.
    package var machO: MachOImage {
        _sharedMachO
    }

    /// Async access to the prepared indexer. The actor cache builds it once
    /// per process and hands every test the same reference, so the awaiter
    /// pays the preparation cost zero times after the first hit.
    package var indexer: SwiftDeclarationIndexer<MachOImage> {
        get async throws {
            try await SharedSpecializationIndexerCache.shared.indexer()
        }
    }

    /// Resolves the first struct context descriptor whose name contains
    /// `nameContains`. Substring matching mirrors how nested fixtures are
    /// referenced in tests; full module-qualified names are not required.
    package func structDescriptor(named nameContains: String) throws -> StructDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.struct?.name(in: machO).contains(nameContains) == true
            }?.struct,
            "expected a struct context descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Resolves a struct descriptor and binds it to the in-process reader via
    /// `asPointerWrapper(in:)`. Required for callers that invoke the
    /// no-argument overloads of descriptor methods (e.g. `genericContext()`),
    /// which read through the descriptor's embedded reader rather than an
    /// explicit `MachOImage` argument.
    package func inProcessStructDescriptor(named nameContains: String) throws -> StructDescriptor {
        try structDescriptor(named: nameContains).asPointerWrapper(in: machO)
    }

    /// Resolves the first enum context descriptor whose name contains
    /// `nameContains`. Mirrors `structDescriptor(named:)` for enum fixtures.
    package func enumDescriptor(named nameContains: String) throws -> EnumDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.enum?.name(in: machO).contains(nameContains) == true
            }?.enum,
            "expected an enum context descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Resolves the first class context descriptor whose name contains
    /// `nameContains`. Mirrors `structDescriptor(named:)` for class fixtures.
    package func classDescriptor(named nameContains: String) throws -> ClassDescriptor {
        try #require(
            try machO.swift.typeContextDescriptors.first {
                try $0.class?.name(in: machO).contains(nameContains) == true
            }?.class,
            "expected a class context descriptor whose name contains \"\(nameContains)\""
        )
    }

    /// Resolves the descriptor along with its generic context. Used by tests
    /// that inspect the generic header (e.g. `numKeyArguments`) in addition
    /// to driving `GenericSpecializer`.
    package func genericStructFixture(
        named nameContains: String
    ) throws -> (descriptor: StructDescriptor, genericContext: GenericContext) {
        let descriptor = try structDescriptor(named: nameContains)
        let genericContext = try #require(
            try descriptor.genericContext(in: machO),
            "expected genericContext on \(nameContains)"
        )
        return (descriptor, genericContext)
    }
}
