import Foundation
import SwiftDeclaration
import SwiftIndexing
import SwiftDeclarationRendering
import SwiftDiffing
import MachOSwiftSection
import Semantic

/// The pack-generic evolution interface builder: the version axis' reader
/// types live in the type's own signature —
/// `SwiftEvolutionInterfaceBuilder<MachOFile, MachOFile, MachOFile>`, or a
/// heterogeneous mix like `<MachOFile, MachOImage>` — for callers whose
/// version list is fixed at compile time.
///
/// A thin façade over ``AnySwiftEvolutionInterfaceBuilder``: construction
/// erases the pack immediately, so behavior is identical by construction —
/// there is exactly one rendering pipeline. Two consequences of the pack
/// living in *type* position:
///
/// - **Availability**: parameter packs in generic types need the Swift 5.9
///   runtime (`parameter packs in generic types are only available in
///   macOS 14.0.0 or newer`), hence the gate — packs in *function* position
///   (the erased builder's heterogeneous initializer) need none.
/// - **Arity is compile-time**: a pack cannot express "N versions decided at
///   runtime". The CLI and any host letting the user pick an arbitrary set of
///   versions use ``AnySwiftEvolutionInterfaceBuilder`` instead.
///
/// See ``AnySwiftEvolutionInterfaceBuilder`` for the pipeline's semantics
/// (union interface, lifecycle annotations, annotation-fact sourcing).
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
public final class SwiftEvolutionInterfaceBuilder<each MachO: FieldLayoutRenderable>: Sendable {
    /// The type-erased core every entry point delegates to. Exposed so a
    /// pack-typed builder can be handed to API that takes the erased form.
    public let erased: AnySwiftEvolutionInterfaceBuilder

    /// One version per pack element, oldest first, labels index-aligned.
    ///
    /// - Throws: `ABIEvolutionError.fewerThanTwoVersions` /
    ///   `.labelCountMismatch` on invalid input shapes.
    public init(
        configuration: SwiftDeclarationIndexConfiguration = .init(),
        eventHandlers: [SwiftIndexEvents.Handler] = [],
        versions: repeat each MachO,
        labels: [String]
    ) throws {
        self.erased = try AnySwiftEvolutionInterfaceBuilder(
            configuration: configuration,
            eventHandlers: eventHandlers,
            versions: repeat each versions,
            labels: labels
        )
    }

    /// The version-axis labels, oldest first.
    public var labels: [String] { erased.labels }

    /// See ``AnySwiftEvolutionInterfaceBuilder/evolution``.
    public var evolution: ABIEvolution? { erased.evolution }

    /// See ``AnySwiftEvolutionInterfaceBuilder/prepare(maximumConcurrentPreparations:)``.
    public func prepare(maximumConcurrentPreparations: Int = ProcessInfo.processInfo.activeProcessorCount) async throws {
        try await erased.prepare(maximumConcurrentPreparations: maximumConcurrentPreparations)
    }

    /// See ``AnySwiftEvolutionInterfaceBuilder/printAnnotatedInterface()``.
    public func printAnnotatedInterface() async throws -> SemanticString {
        try await erased.printAnnotatedInterface()
    }

    /// See ``AnySwiftEvolutionInterfaceBuilder/annotatedBlocks()``.
    @_spi(Support)
    public func annotatedBlocks() async throws -> [[EvolutionLine]] {
        try await erased.annotatedBlocks()
    }
}
