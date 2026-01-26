import Foundation
import Demangling
import MachOSwiftSection

/// Specialization request - describes generic parameters and constraints of a type
public struct SpecializationRequest: Sendable {
    /// Target type descriptor
    public let typeDescriptor: TypeContextDescriptorWrapper

    /// Generic parameters in declaration order
    public let parameters: [Parameter]

    /// Associated type constraints (e.g., A.Element: Hashable)
    public let associatedTypeConstraints: [AssociatedTypeConstraint]

    /// Total number of key arguments required
    public let keyArgumentCount: Int

    public init(
        typeDescriptor: TypeContextDescriptorWrapper,
        parameters: [Parameter],
        associatedTypeConstraints: [AssociatedTypeConstraint],
        keyArgumentCount: Int
    ) {
        self.typeDescriptor = typeDescriptor
        self.parameters = parameters
        self.associatedTypeConstraints = associatedTypeConstraints
        self.keyArgumentCount = keyArgumentCount
    }
}

// MARK: - Parameter

extension SpecializationRequest {
    /// Generic parameter with its constraints and candidate types
    public struct Parameter: Sendable {
        /// Parameter name (e.g., "T", "Element")
        public let name: String

        /// Parameter index in generic signature
        public let index: Int

        /// Depth level (for nested generic contexts)
        public let depth: Int

        /// Constraints on this parameter
        public let constraints: [Constraint]

        /// Candidate types that satisfy all constraints
        public var candidates: [Candidate]

        public init(
            name: String,
            index: Int,
            depth: Int,
            constraints: [Constraint],
            candidates: [Candidate] = []
        ) {
            self.name = name
            self.index = index
            self.depth = depth
            self.constraints = constraints
            self.candidates = candidates
        }

        /// Protocol constraints that require witness tables
        public var protocolConstraints: [Constraint] {
            constraints.filter {
                if case .protocol = $0 { return true }
                return false
            }
        }

        /// Whether this parameter has any protocol constraints
        public var hasProtocolConstraints: Bool {
            !protocolConstraints.isEmpty
        }
    }
}

// MARK: - Constraint

extension SpecializationRequest {
    /// Constraint on a generic parameter
    public enum Constraint: Sendable, Hashable {
        /// Protocol conformance constraint (T: SomeProtocol) - requires PWT
        case `protocol`(ProtocolConstraintInfo)

        /// Same type constraint (T == U) - validation only
        case sameType(mangledTypeName: String)

        /// Base class constraint (T: SomeClass) - validation only
        case baseClass(mangledTypeName: String)

        /// Layout constraint (T: AnyObject, T: _Trivial) - validation only
        case layout(LayoutKind)
    }

    /// Protocol constraint information
    public struct ProtocolConstraintInfo: Sendable, Hashable {
        /// Protocol name
        public let protocolName: ProtocolName

        /// Whether this constraint requires a witness table (is key argument)
        public let requiresWitnessTable: Bool

        public init(protocolName: ProtocolName, requiresWitnessTable: Bool) {
            self.protocolName = protocolName
            self.requiresWitnessTable = requiresWitnessTable
        }
    }

    /// Layout constraint kind
    public enum LayoutKind: Sendable, Hashable {
        case `class`
        case nativeClass
        case refCountedObject
        case nativeRefCountedObject
        case trivial
        case trivialOfExactSize(Int)
        case trivialOfAtMostSize(Int)
        case unknown(Int)
    }
}

// MARK: - Candidate

extension SpecializationRequest {
    /// A candidate type that can be used for specialization
    public struct Candidate: Sendable, Hashable {
        /// Type name
        public let typeName: TypeName

        /// Type kind (enum, struct, class)
        public let kind: TypeKind

        /// Source of this candidate
        public let source: Source

        /// Whether this type is generic and requires further specialization
        public let isGeneric: Bool

        /// Generic parameter names if this is a generic type
        public let genericParameterNames: [String]?

        public init(
            typeName: TypeName,
            kind: TypeKind,
            source: Source,
            isGeneric: Bool = false,
            genericParameterNames: [String]? = nil
        ) {
            self.typeName = typeName
            self.kind = kind
            self.source = source
            self.isGeneric = isGeneric
            self.genericParameterNames = genericParameterNames
        }

        /// Source of candidate type
        public enum Source: Sendable, Hashable {
            /// From indexed MachO file
            case indexed(machOName: String)

            /// From Swift standard library
            case standardLibrary

            /// From runtime (user-provided)
            case runtime
        }
    }
}

// MARK: - AssociatedTypeConstraint

extension SpecializationRequest {
    /// Constraint on an associated type (e.g., A.Element: Hashable)
    public struct AssociatedTypeConstraint: Sendable {
        /// Base parameter name (e.g., "A" in A.Element)
        public let parameterName: String

        /// Associated type path (e.g., ["Element"] or ["Iterator", "Element"])
        public let path: [String]

        /// Constraints on the associated type
        public let constraints: [Constraint]

        public init(
            parameterName: String,
            path: [String],
            constraints: [Constraint]
        ) {
            self.parameterName = parameterName
            self.path = path
            self.constraints = constraints
        }

        /// Full path string (e.g., "A.Element")
        public var fullPath: String {
            ([parameterName] + path).joined(separator: ".")
        }
    }
}
