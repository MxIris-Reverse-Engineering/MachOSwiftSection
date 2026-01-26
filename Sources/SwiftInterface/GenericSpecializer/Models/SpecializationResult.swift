import Foundation
import MachOSwiftSection
import OrderedCollections

/// Result of generic type specialization
public struct SpecializationResult: @unchecked Sendable {
    /// Specialized metadata
    public let metadata: Metadata

    /// Type layout information
    public let layout: Layout

    /// Field information with offsets
    public let fields: [Field]

    /// Resolved generic arguments used for specialization
    public let resolvedArguments: [ResolvedArgument]

    public init(
        metadata: Metadata,
        layout: Layout,
        fields: [Field],
        resolvedArguments: [ResolvedArgument]
    ) {
        self.metadata = metadata
        self.layout = layout
        self.fields = fields
        self.resolvedArguments = resolvedArguments
    }
}

// MARK: - Layout

extension SpecializationResult {
    /// Type layout information
    public struct Layout: Sendable, Hashable {
        /// Size in bytes
        public let size: Int

        /// Alignment requirement in bytes
        public let alignment: Int

        /// Stride in bytes (size rounded up to alignment)
        public let stride: Int

        /// Whether this is a Plain Old Data type (no reference counting)
        public let isPOD: Bool

        /// Whether the type can be stored inline in a container
        public let isInline: Bool

        /// Number of extra inhabitants available for optimization
        public let extraInhabitantCount: Int

        public init(
            size: Int,
            alignment: Int,
            stride: Int,
            isPOD: Bool,
            isInline: Bool,
            extraInhabitantCount: Int
        ) {
            self.size = size
            self.alignment = alignment
            self.stride = stride
            self.isPOD = isPOD
            self.isInline = isInline
            self.extraInhabitantCount = extraInhabitantCount
        }

        /// Create layout with minimal information
        public init(size: Int, alignment: Int, stride: Int) {
            self.size = size
            self.alignment = alignment
            self.stride = stride
            self.isPOD = false
            self.isInline = size <= 3 * MemoryLayout<Int>.size
            self.extraInhabitantCount = 0
        }
    }
}

// MARK: - Field

extension SpecializationResult {
    /// Specialized field information
    public struct Field: Sendable {
        /// Field name
        public let name: String

        /// Field offset in bytes
        public let offset: UInt32

        /// Mangled type name of the field
        public let mangledTypeName: String

        /// Field metadata if available
        public let metadata: Metadata?

        /// Whether the field is a let constant
        public let isLet: Bool

        /// Whether the field is a var
        public var isVar: Bool { !isLet }

        public init(
            name: String,
            offset: UInt32,
            mangledTypeName: String,
            metadata: Metadata? = nil,
            isLet: Bool = true
        ) {
            self.name = name
            self.offset = offset
            self.mangledTypeName = mangledTypeName
            self.metadata = metadata
            self.isLet = isLet
        }
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
    /// Get field by name
    public func field(named name: String) -> Field? {
        fields.first { $0.name == name }
    }

    /// Get field offset by name
    public func offset(of fieldName: String) -> UInt32? {
        field(named: fieldName)?.offset
    }

    /// Get all field offsets as an ordered dictionary
    public var fieldOffsetsByName: OrderedDictionary<String, UInt32> {
        OrderedDictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.offset) })
    }

    /// Get resolved argument for a parameter
    public func argument(for parameterName: String) -> ResolvedArgument? {
        resolvedArguments.first { $0.parameterName == parameterName }
    }
}
