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
        let witnesses = Self.witnesses(for: builtRequirements, ofProtocolRuntimeName: record.runtimeName, in: machO)
        requirements = builtRequirements.enumerated().map { index, requirement in
            let witness = witnesses[index]
            return ObjCProtocolRequirementDefinition(
                kind: Self.kind(of: requirement),
                node: InternedNodeReferenceCache.shared.reference(interning: witness?.node ?? requirement.node, in: machO),
                selector: requirement.selector,
                setterSelector: requirement.setterSelector,
                isClassMember: requirement.isClassMember,
                isOptional: requirement.isOptional,
                source: witness.map { .conformer(className: $0.className) } ?? .selector,
                hasExplicitSelector: witness?.hasExplicitSelector ?? true,
                typeEncoding: requirement.typeEncoding
            )
        }
    }

    private static func kind(of requirement: ObjCProtocolRequirement) -> ObjCProtocolRequirementDefinition.Kind {
        switch requirement.kind {
        case .method: .method
        case .initializer: .initializer
        case .property: .property
        case .subscript: .subscript
        }
    }

    private struct Witness {
        let node: Node
        let className: String
        let hasExplicitSelector: Bool
    }

    /// For each requirement, the member implementing it in a Swift class of
    /// the image adopting the protocol — directly, or through one of the
    /// image's protocols refining it — tied to the class's method by a
    /// symbol or thunk at the method's implementation, never by the name
    /// alone. Classes are asked in class-list order, and the search stops
    /// once every requirement has one.
    private static func witnesses(for requirements: [ObjCProtocolRequirement], ofProtocolRuntimeName protocolRuntimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> [Int: Witness] {
        guard !requirements.isEmpty else { return [:] }
        var protocolRuntimeNames: [String] = [protocolRuntimeName]
        let records = SwiftDeclaredObjCProtocolIndex.shared.protocols(in: machO).compactMap(\.record)
        var didGrow = true
        while didGrow {
            didGrow = false
            for record in records where !protocolRuntimeNames.contains(record.runtimeName) && record.inheritedProtocolRuntimeNames.contains(where: protocolRuntimeNames.contains) {
                protocolRuntimeNames.append(record.runtimeName)
                didGrow = true
            }
        }
        var adopterRuntimeNames: [String] = []
        for runtimeName in protocolRuntimeNames {
            for adopter in ObjCProtocolAdoptionIndex.shared.adopterClassRuntimeNames(ofProtocolRuntimeName: runtimeName, in: machO) where !adopterRuntimeNames.contains(adopter) {
                adopterRuntimeNames.append(adopter)
            }
        }

        var witnesses: [Int: Witness] = [:]
        for adopterRuntimeName in adopterRuntimeNames where witnesses.count < requirements.count {
            guard let table = ObjCMembers.table(forObjCClassNamed: adopterRuntimeName, in: machO),
                  let classNode = ObjCRuntimeNames.swiftClassNode(forRuntimeName: adopterRuntimeName, in: machO),
                  let className = NodeTypeNaming.nominalQualifiedName(of: classNode)
            else { continue }
            // Selector and kind → the members tied to it, a deterministic
            // pick among identical-code-folded twins.
            var symbolNamesByMethod: [MethodKey: [String]] = [:]
            for (symbolName, member) in table.membersByImplementationSymbolName where member.evidence != .selectorName {
                symbolNamesByMethod[MethodKey(selector: member.selector, isClassMethod: member.isClassMethod), default: []].append(symbolName)
            }
            for (index, requirement) in requirements.enumerated() where witnesses[index] == nil {
                let key = MethodKey(selector: requirement.selector, isClassMethod: requirement.isClassMember)
                for symbolName in (symbolNamesByMethod[key] ?? []).sorted() {
                    guard let node = declarationNode(ofMemberSymbolNamed: symbolName, for: requirement.kind) else { continue }
                    witnesses[index] = Witness(node: node, className: className, hasExplicitSelector: table.membersByImplementationSymbolName[symbolName]?.hasExplicitSelector ?? false)
                    break
                }
            }
        }
        return witnesses
    }

    private struct MethodKey: Hashable {
        let selector: String
        let isClassMethod: Bool
    }

    /// The member's declaration, as a requirement prints it: the `@objc`
    /// thunk's marker dropped, an initializer's initializing entry point read
    /// as the allocating one the printer recognizes. A symbol of another
    /// kind than the requirement's — a property's setter where its getter
    /// was asked for — is no witness.
    private static func declarationNode(ofMemberSymbolNamed symbolName: String, for kind: ObjCProtocolRequirement.Kind) -> Node? {
        guard let root = try? demangleAsNodeTransient(symbolName), root.kind == .global else { return nil }
        let entities = root.children.filter { $0.kind != .objCAttribute }
        guard entities.count == 1, let entity = entities.first else { return nil }
        let declaration = entity.kind == .static ? entity.firstChild : entity
        guard let declaration else { return nil }
        let rebuiltDeclaration: Node
        switch (kind, declaration.kind) {
        case (.method, .function):
            rebuiltDeclaration = declaration
        case (.initializer, .allocator):
            rebuiltDeclaration = declaration
        case (.initializer, .constructor):
            rebuiltDeclaration = Node.createTransient(kind: .allocator, children: Array(declaration.children))
        case (.property, .getter) where declaration.firstChild?.kind == .variable:
            rebuiltDeclaration = declaration
        case (.subscript, .getter) where declaration.firstChild?.kind == .subscript:
            rebuiltDeclaration = declaration
        default:
            return nil
        }
        let entityNode = entity.kind == .static ? Node.createTransient(kind: .static, child: rebuiltDeclaration) : rebuiltDeclaration
        return Node.createTransient(kind: .global, child: entityNode)
    }
}
