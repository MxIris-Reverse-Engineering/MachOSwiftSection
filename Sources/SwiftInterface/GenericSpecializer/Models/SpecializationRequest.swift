import Foundation
import Demangling
import MachOSwiftSection

/// Specialization request - describes generic parameters and requirements of a type
public struct SpecializationRequest: Sendable {
    /// Target type descriptor
    public let typeDescriptor: TypeContextDescriptorWrapper

    /// Generic parameters in declaration order
    public let parameters: [Parameter]

    /// Associated type requirements (e.g., A.Element: Hashable)
    public let associatedTypeRequirements: [AssociatedTypeRequirement]

    /// Total number of key arguments required
    public let keyArgumentCount: Int

    public init(
        typeDescriptor: TypeContextDescriptorWrapper,
        parameters: [Parameter],
        associatedTypeRequirements: [AssociatedTypeRequirement],
        keyArgumentCount: Int
    ) {
        self.typeDescriptor = typeDescriptor
        self.parameters = parameters
        self.associatedTypeRequirements = associatedTypeRequirements
        self.keyArgumentCount = keyArgumentCount
    }
}

// MARK: - Parameter

extension SpecializationRequest {
    /// Generic parameter with its requirements and candidate types
    public struct Parameter: Sendable {
        /// Parameter name (e.g., "A", "B", "A1" - based on depth and index)
        public let name: String

        /// Parameter index in generic signature
        public let index: Int

        /// Depth level (for nested generic contexts)
        public let depth: Int

        /// Requirements on this parameter (ordered - PWT passed in this order)
        public let requirements: [Requirement]

        /// Candidate types that satisfy all requirements
        public var candidates: [Candidate]

        public init(
            name: String,
            index: Int,
            depth: Int,
            requirements: [Requirement],
            candidates: [Candidate] = []
        ) {
            self.name = name
            self.index = index
            self.depth = depth
            self.requirements = requirements
            self.candidates = candidates
        }

        /// Protocol requirements that require witness tables (in order)
        public var protocolRequirements: [Requirement] {
            requirements.filter {
                if case .protocol = $0 { return true }
                return false
            }
        }

        /// Whether this parameter has any protocol requirements
        public var hasProtocolRequirements: Bool {
            !protocolRequirements.isEmpty
        }
    }
}

// MARK: - Requirement

extension SpecializationRequest {
    /// Requirement on a generic parameter
    public enum Requirement: Sendable, Hashable {
        /// Protocol conformance requirement (A: SomeProtocol) - requires PWT
        case `protocol`(ProtocolRequirementInfo)

        /// Same type requirement (A == B) - validation only
        case sameType(demangledTypeNode: Node)

        /// Base class requirement (A: SomeClass) - validation only
        case baseClass(demangledTypeNode: Node)

        /// Layout requirement (A: AnyObject) - validation only
        case layout(LayoutKind)
    }

    /// Protocol requirement information
    public struct ProtocolRequirementInfo: Sendable, Hashable {
        /// Protocol name
        public let protocolName: ProtocolName

        /// Whether this requirement requires a witness table (is key argument)
        public let requiresWitnessTable: Bool

        public init(protocolName: ProtocolName, requiresWitnessTable: Bool) {
            self.protocolName = protocolName
            self.requiresWitnessTable = requiresWitnessTable
        }
    }

    /// Layout requirement kind
    public enum LayoutKind: Sendable, Hashable {
        case `class`
    }
}

// MARK: - Candidate

extension SpecializationRequest {
    /// A candidate type that can be used for specialization
    public struct Candidate: Sendable, Hashable {
        /// Type name
        public let typeName: TypeName

        /// Source of this candidate
        public let source: Source

        public init(
            typeName: TypeName,
            source: Source,
        ) {
            self.typeName = typeName
            self.source = source
        }

        /// Source of candidate type
        public enum Source: Sendable, Hashable {
            case image(String)
        }
    }
}

// MARK: - AssociatedTypeRequirement

extension SpecializationRequest {
    /// Requirement on an associated type (e.g., A.Element: Hashable)
    public struct AssociatedTypeRequirement: Sendable {
        /// Base parameter name (e.g., "A" in A.Element)
        public let parameterName: String

        /// Associated type path (e.g., ["Element"] or ["Iterator", "Element"])
        public let path: [String]

        /// Requirements on the associated type (ordered - PWT passed in this order)
        public let requirements: [Requirement]

        public init(
            parameterName: String,
            path: [String],
            requirements: [Requirement]
        ) {
            self.parameterName = parameterName
            self.path = path
            self.requirements = requirements
        }

        /// Full path string (e.g., "A.Element")
        public var fullPath: String {
            ([parameterName] + path).joined(separator: ".")
        }
    }
}
