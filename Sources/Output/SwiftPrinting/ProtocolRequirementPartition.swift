import MachOSwiftSection
import Demangling
import SwiftDeclarationRendering
@_spi(Internals) import SwiftInspection

/// A protocol's requirement signature split by where each requirement prints
/// (evolution proposal `protocol-requirement-placement`).
///
/// Every requirement lands in exactly one list, each list keeps the
/// signature's order, and a requirement prints the same words wherever it
/// lands — an inheritance clause only leaves out the `Self.Item:` it is
/// attached to. So both placements state the same requirements by
/// construction; where one lands is the only thing that differs.
package struct ProtocolRequirementPartition {
    /// The protocol's inheritance clause: requirements on `Self` itself.
    package private(set) var protocolInheritanceClause: [GenericRequirement] = []

    /// The protocol's `where` clause.
    package private(set) var protocolWhereClause: [GenericRequirement] = []

    /// Each associated type's inheritance clause, by associated type name.
    package private(set) var associatedTypeInheritanceClauses: [String: [GenericRequirement]] = [:]

    /// Each associated type's `where` clause, by associated type name.
    package private(set) var associatedTypeWhereClauses: [String: [GenericRequirement]] = [:]

    /// `associatedTypeNames` are the protocol's own associated types, the
    /// ones its descriptor lists; `.protocolWhereClause` never reads them.
    package init(requirements: [GenericRequirement], associatedTypeNames: [String], placement: ProtocolRequirementPlacement, in context: some ReadingContext) {
        let ownAssociatedTypeNames = Set(associatedTypeNames)
        for requirement in requirements {
            if requirement.isProtocolInherited {
                protocolInheritanceClause.append(requirement)
                continue
            }
            switch placement {
            case .protocolWhereClause:
                protocolWhereClause.append(requirement)
            case .associatedTypes:
                switch Self.location(of: requirement, among: ownAssociatedTypeNames, in: context) {
                case .associatedTypeInheritanceClause(let associatedTypeName):
                    associatedTypeInheritanceClauses[associatedTypeName, default: []].append(requirement)
                case .associatedTypeWhereClause(let associatedTypeName):
                    associatedTypeWhereClauses[associatedTypeName, default: []].append(requirement)
                case nil:
                    protocolWhereClause.append(requirement)
                }
            }
        }
    }

    private enum Location {
        case associatedTypeInheritanceClause(String)
        case associatedTypeWhereClause(String)
    }

    /// Where `requirement` prints under `.associatedTypes`; `nil` is the
    /// protocol's `where` clause.
    ///
    /// Only a conformance, superclass or layout requirement on exactly
    /// `Self.Item` goes into `Item`'s inheritance clause — the one placement
    /// that would change the meaning if it took the wrong associated type.
    /// The compiler's own printer does take the wrong one for a member of a
    /// member: `Self.Child.Leaf: Hashable` of a recursive protocol reads
    /// `associatedtype Leaf: Hashable` in its `.swiftinterface`, a stronger
    /// requirement on `Self.Leaf`. Any other requirement goes into the
    /// `where` clause of the associated type its member chain starts from
    /// (`Self.Child.Leaf` starts from `Child`); a same-type requirement takes
    /// a side that is exactly `Self.Item` first, then the left side's chain,
    /// then the right's. Inverse and same-shape requirements stay where they
    /// were. A `where` clause takes any requirement about `Self`, so none of
    /// this can change what the requirements say.
    private static func location(of requirement: GenericRequirement, among associatedTypeNames: Set<String>, in context: some ReadingContext) -> Location? {
        guard let subject = try? SymbolicDemangler.demangleType(for: requirement.paramManagledName, in: context) else { return nil }
        switch requirement.descriptor.flags.kind {
        case .protocol, .baseClass, .layout:
            if let associatedTypeName = directAssociatedTypeName(of: subject, among: associatedTypeNames) {
                return .associatedTypeInheritanceClause(associatedTypeName)
            }
            return subject.firstProtocolSelfMemberRoot(among: associatedTypeNames).map(Location.associatedTypeWhereClause)
        case .sameType:
            var sides = [subject]
            if case .type(let mangledName) = requirement.content, let rightHandSide = try? SymbolicDemangler.demangleType(for: mangledName, in: context) {
                sides.append(rightHandSide)
            }
            if let associatedTypeName = sides.lazy.compactMap({ directAssociatedTypeName(of: $0, among: associatedTypeNames) }).first {
                return .associatedTypeWhereClause(associatedTypeName)
            }
            return sides.lazy.compactMap { $0.firstProtocolSelfMemberRoot(among: associatedTypeNames) }.first.map(Location.associatedTypeWhereClause)
        default:
            return nil
        }
    }

    /// `Item` when `type` is exactly `Self.Item` and `Item` is one of
    /// `associatedTypeNames`.
    private static func directAssociatedTypeName(of type: Node, among associatedTypeNames: Set<String>) -> String? {
        guard let memberNames = type.protocolSelfMemberNames, memberNames.count == 1, let associatedTypeName = memberNames.first, associatedTypeNames.contains(associatedTypeName) else { return nil }
        return associatedTypeName
    }
}
