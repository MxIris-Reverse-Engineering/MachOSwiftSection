import MachOSwiftSection
import Semantic
import SwiftDeclarationRendering

/// A protocol requirement whose symbolic reference the binary no longer
/// carries — the requirement slot is there, the symbol that would name it was
/// stripped. `ProtocolDefinition` keeps these so a stripped requirement still
/// occupies its witness-table position in the output instead of vanishing.
public struct StrippedSymbolicRequirement: Sendable {
    public let requirement: ProtocolRequirement
    public let pwtOffset: Int
}

extension StrippedSymbolicRequirement {
    /// Mach-O-free facts about the stripped requirement, exposed so consumers
    /// that must not touch Mach-O types (SwiftDiffing keys its ABI records on
    /// these) get a stable facade. `kindToken` is an explicit switch — the
    /// tokens are part of the persisted ABI-key scheme, so renaming one is a
    /// key-scheme change (bump `ABISnapshotDocument.currentFormatVersion`).
    public var kindToken: String {
        switch requirement.layout.flags.kind {
        case .baseProtocol: return "baseProtocol"
        case .method: return "method"
        case .`init`: return "init"
        case .getter: return "getter"
        case .setter: return "setter"
        case .readCoroutine: return "readCoroutine"
        case .modifyCoroutine: return "modifyCoroutine"
        case .associatedTypeAccessFunction: return "associatedTypeAccessFunction"
        case .associatedConformanceAccessFunction: return "associatedConformanceAccessFunction"
        }
    }

    public var isInstance: Bool {
        requirement.layout.flags.isInstance
    }

    public var isAsync: Bool {
        requirement.layout.flags.isAsync
    }

    /// Whether the requirement carries a default implementation (a valid
    /// relative pointer — pure arithmetic, no resolution).
    public var hasDefaultImplementation: Bool {
        requirement.layout.defaultImplementation.isValid
    }
}

extension StrippedSymbolicRequirement {
    @SemanticStringBuilder
    package func strippedSymbolicInfo() -> SemanticString {
        Comment(
            """
            Kind: \(requirement.layout.flags.kind.description), isAsync: \(requirement.layout.flags.isAsync), isInstance: \(requirement.layout.flags.isInstance)
            """
        )
    }
}
