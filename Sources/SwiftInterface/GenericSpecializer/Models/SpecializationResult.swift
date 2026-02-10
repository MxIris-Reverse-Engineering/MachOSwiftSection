import Foundation
import MachOSwiftSection
import OrderedCollections

/// Result of generic type specialization
public struct SpecializationResult: @unchecked Sendable {
    /// Specialized metadata pointer
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

    /// Get field offsets from the specialized metadata (struct only)
    /// - Returns: Array of field offsets in bytes
    public func fieldOffsets() throws -> [UInt32] {
        let wrapper = try resolveMetadata()
        switch wrapper {
        case .struct(let structMetadata):
            return try structMetadata.fieldOffsets()
        default:
            return []
        }
    }

    /// Get field offsets from the specialized metadata with MachO context
    /// - Parameter machO: The MachO image
    /// - Returns: Array of field offsets in bytes
    public func fieldOffsets<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> [UInt32] {
        let wrapper = try resolveMetadata()
        switch wrapper {
        case .struct(let structMetadata):
            return try structMetadata.fieldOffsets(in: machO)
        default:
            return []
        }
    }

    /// Get the value witness table for layout information
    public func valueWitnessTable() throws -> ValueWitnessTable {
        let wrapper = try resolveMetadata()
        return try wrapper.valueWitnessTable()
    }

    /// Get the value witness table with MachO context
    public func valueWitnessTable<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> ValueWitnessTable {
        let wrapper = try resolveMetadata()
        return try wrapper.valueWitnessTable(in: machO)
    }
}
