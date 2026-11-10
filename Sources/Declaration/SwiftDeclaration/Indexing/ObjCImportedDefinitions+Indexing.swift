import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

// The indexing passes of the imported Objective-C declarations (evolution
// proposal `objc-imported-declarations`). Each is synchronous, runs once
// behind `DefinitionIndexing`'s lock, and indexes no other definition: the
// Swift definitions a class or category is paired with are indexed by the
// printer, which pairs them by selector.

extension ObjCImportedClassDefinition: OnceIndexedDefinition {
    /// Reads the superclass, the protocols and the members. Idempotent, and
    /// safe to call from several tasks at once.
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            runIndexingPass(in: machO)
        }
    }

    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard let classNode = className.node.materialize().first(of: .class) else { return }
        superclassName = record.superclassRuntimeName.map { ObjCImportedDefinitionNames.typeName(ofClassRuntimeName: $0, in: machO) }
        protocolNames = record.protocolRuntimeNames.map { ObjCImportedDefinitionNames.protocolName(ofRuntimeName: $0, in: machO) }
        members = ObjCImportedMemberBuilder.members(of: record, contextNode: classNode, contextTypeName: classNode.identifier ?? record.classRuntimeName, in: machO)
            .map { ObjCImportedMemberDefinition(member: $0, in: machO) }
    }
}

extension ObjCImportedCategoryDefinition: OnceIndexedDefinition {
    /// Reads the protocols and the members.
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            runIndexingPass(in: machO)
        }
    }

    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard let classNode = extendedClassName.node.materialize().first(of: .class) else { return }
        protocolNames = record.protocolRuntimeNames.map { ObjCImportedDefinitionNames.protocolName(ofRuntimeName: $0, in: machO) }
        members = ObjCImportedMemberBuilder.members(of: record, contextNode: classNode, contextTypeName: classNode.identifier ?? record.classRuntimeName, in: machO)
            .map { ObjCImportedMemberDefinition(member: $0, in: machO) }
    }
}

extension ObjCImportedProtocolDefinition: OnceIndexedDefinition {
    /// Reads the inherited protocols and the requirements.
    package func index(in machO: some MachOSwiftSectionRepresentableWithCache) throws {
        try DefinitionIndexing.index(self) {
            runIndexingPass(in: machO)
        }
    }

    private func runIndexingPass(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard let protocolNode = protocolName.node.materialize().first(of: .protocol) else { return }
        inheritedProtocolNames = record.inheritedProtocolRuntimeNames.map { ObjCImportedDefinitionNames.protocolName(ofRuntimeName: $0, in: machO) }
        requirements = ObjCProtocolRequirementBuilder.requirements(of: record, protocolNode: protocolNode, declaredIn: .objectiveC, in: machO).map { requirement in
            let kind: ObjCProtocolRequirementDefinition.Kind = switch requirement.kind {
            case .method: .method
            case .initializer: .initializer
            case .property: .property
            case .subscript: .subscript
            }
            return ObjCProtocolRequirementDefinition(
                kind: kind,
                node: InternedNodeReferenceCache.shared.reference(interning: requirement.node, in: machO),
                selector: requirement.selector,
                setterSelector: requirement.setterSelector,
                isClassMember: requirement.isClassMember,
                isOptional: requirement.isOptional,
                origin: .selector,
                hasExplicitSelector: requirement.hasExplicitSelector,
                typeEncoding: requirement.typeEncoding
            )
        }
    }
}

extension ObjCImportedMemberDefinition {
    package init(member: ObjCImportedMember, in machO: some MachOSwiftSectionRepresentableWithCache) {
        let kind: Kind = switch member.kind {
        case .method: .method
        case .initializer: .initializer
        case .factoryInitializer: .factoryInitializer
        case .property: .property
        case .subscript: .subscript
        }
        let ownership: Ownership? = member.ownership.map { ownership in
            switch ownership {
            case .strong: .strong
            case .copy: .copy
            case .weak: .weak
            case .unownedUnsafe: .unownedUnsafe
            }
        }
        self.init(
            kind: kind,
            node: InternedNodeReferenceCache.shared.reference(interning: member.node, in: machO),
            selector: member.selector,
            setterSelector: member.setterSelector,
            isClassMember: member.isClassMember,
            ownership: ownership,
            hasExplicitSelector: member.hasExplicitSelector,
            typeEncoding: member.typeEncoding
        )
    }
}

/// The names an imported declaration's header prints, from runtime names.
enum ObjCImportedDefinitionNames {
    static func typeName(ofClassRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> TypeName {
        let typeNode = Node.createTransient(kind: .type, child: ObjCRuntimeNames.classNode(forRuntimeName: runtimeName, in: machO))
        return TypeName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO), kind: .class)
    }

    static func protocolName(ofRuntimeName runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> ProtocolName {
        let typeNode = Node.createTransient(kind: .type, child: ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO))
        return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO))
    }
}
