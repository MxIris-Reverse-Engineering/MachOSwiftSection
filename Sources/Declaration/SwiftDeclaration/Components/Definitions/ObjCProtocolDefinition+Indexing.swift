import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
import SwiftThunkAnalysis
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension ObjCProtocolDefinition: OnceIndexedDefinition {
    /// Reads the inherited protocols and the requirements. Idempotent, and
    /// safe to call from several tasks at once: the first runs the pass, the
    /// others wait for it (`DefinitionIndexing`).
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            runIndexingPass(in: machO)
        }
    }

    /// The pass `index(in:)` runs once. Synchronous, and it never indexes
    /// another definition: a conformer's member is read from the class's
    /// Objective-C member table, not from its `TypeDefinition`.
    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) {
        // Unpaired: the image holds no record to read requirements from.
        guard let record = declaredProtocol.record,
              let protocolNode = protocolName.node.materialize().first(of: .protocol)
        else { return }

        inheritedProtocolNames = record.inheritedProtocolRuntimeNames.map { runtimeName in
            let typeNode = Node.createTransient(kind: .type, child: ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO))
            return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO))
        }

        let builtRequirements = ObjCProtocolRequirementBuilder.requirements(of: record, protocolNode: protocolNode, in: machO)
        let witnesses = ObjCProtocolWitnesses.witnesses(for: builtRequirements, ofProtocolRuntimeName: record.runtimeName, protocolNode: protocolNode, in: machO)
        requirements = builtRequirements.enumerated().map { index, requirement in
            let witness = witnesses[index]
            return ObjCProtocolRequirementDefinition(
                kind: Self.kind(of: requirement),
                node: InternedNodeReferenceCache.shared.reference(interning: witness?.node ?? requirement.node, in: machO),
                selector: requirement.selector,
                setterSelector: requirement.setterSelector,
                isClassMember: requirement.isClassMember,
                isOptional: requirement.isOptional,
                source: witness.map { .conformer(className: Self.className(of: $0, in: machO)) } ?? .selector,
                hasExplicitSelector: witness?.hasExplicitSelector ?? true,
                typeEncoding: requirement.typeEncoding
            )
        }
    }

    /// `Type > Class`, the shape a type definition's name takes.
    private static func className(of witness: ObjCProtocolWitness, in machO: some MachOSwiftSectionRepresentableWithCache) -> TypeName {
        let typeNode = Node.createTransient(kind: .type, child: witness.classNode)
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: .class)
    }

    private static func kind(of requirement: ObjCProtocolRequirement) -> ObjCProtocolRequirementDefinition.Kind {
        switch requirement.kind {
        case .method: .method
        case .initializer: .initializer
        case .property: .property
        case .subscript: .subscript
        }
    }
}
