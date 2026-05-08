import Foundation
import MachOSwiftSection

/// Result of generic type specialization.
///
/// Specialized metadata is allocated by the Swift runtime's metadata
/// allocator (via `swift_getGenericMetadata`) and lives in a runtime-
/// owned heap that is **not part of any MachO image** — neither the
/// type's defining image nor `MachOImage.current()` can claim it.
/// Consequently every accessor on this type and its `ResolvedArgument`
/// pointers operates exclusively in process memory; there is no
/// file-context overload because there is no file backing the data.
public struct SpecializationResult: @unchecked Sendable {
    /// Pointer to the specialized metadata, in process memory. Never
    /// resolves through a MachO file reader — the metadata cache that
    /// `swift_getGenericMetadata` writes into is independent of any
    /// loaded image.
    public let metadataPointer: Pointer<MetadataWrapper>

    /// Resolved generic arguments used for specialization
    public let resolvedArguments: [ResolvedArgument]

    public init(
        metadataPointer: Pointer<MetadataWrapper>,
        resolvedArguments: [ResolvedArgument]
    ) {
        self.metadataPointer = metadataPointer
        self.resolvedArguments = resolvedArguments
    }

    /// Get resolved metadata wrapper
    public func resolveMetadata() throws -> MetadataWrapper {
        try metadataPointer.resolve()
    }

    /// Get resolved metadata
    public func metadata() throws -> Metadata {
        try resolveMetadata().metadata
    }
}

// MARK: - ResolvedArgument

extension SpecializationResult {
    /// A resolved generic argument with its metadata and optional witness table
    public struct ResolvedArgument: @unchecked Sendable {
        /// Parameter name this argument is for
        public let parameterName: String

        /// Resolved metadata for the argument
        public let metadata: Metadata

        /// Protocol witness tables for protocol constraints
        public let witnessTables: [ProtocolWitnessTable]

        public init(
            parameterName: String,
            metadata: Metadata,
            witnessTables: [ProtocolWitnessTable] = []
        ) {
            self.parameterName = parameterName
            self.metadata = metadata
            self.witnessTables = witnessTables
        }

        /// Whether this argument has any witness tables
        public var hasWitnessTables: Bool {
            !witnessTables.isEmpty
        }
    }
}

// MARK: - Convenience Accessors

extension SpecializationResult {
    /// Get resolved argument for a parameter
    public func argument(for parameterName: String) -> ResolvedArgument? {
        resolvedArguments.first { $0.parameterName == parameterName }
    }

    /// Get the value witness table for layout information. Resolves
    /// in-process; specialized metadata never resides in a MachO image,
    /// so the file-context overload of `MetadataWrapper.valueWitnessTable`
    /// would crash with SIGBUS and is intentionally not exposed here.
    public func valueWitnessTable() throws -> ValueWitnessTable {
        let wrapper = try resolveMetadata()
        return try wrapper.valueWitnessTable()
    }
}
