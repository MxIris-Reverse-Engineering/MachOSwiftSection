import Foundation
import MachOKit
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import SwiftInspection

/// The member implementing one requirement of an `@objc` protocol declared
/// in Swift, in a class of the image (evolution proposal
/// `swift-declared-objc-protocols`).
package struct ObjCProtocolWitness: Sendable {
    /// The member's declaration in a requirement's shape, `Global >
    /// Function`, `Global > Static > Getter > Variable`, `Global > Allocator`,
    /// declared in the protocol rather than in the class: its name, labels
    /// and types are the member's.
    package let node: Node
    /// The implementing class: a Swift class, or the Objective-C class the
    /// image extends in a category.
    package let classNode: Node
    /// The symbol the declaration was read from: the `@objc` thunk at the
    /// method's implementation, or the implementation the thunk references.
    package let symbolName: String
    package let evidence: ObjCMember.Evidence
    /// Whether the declaration needs `@objc(selector)`: the compiler derives
    /// another selector from the member's Swift name.
    package let hasExplicitSelector: Bool
}

/// Finds, for each requirement of an `@objc` protocol declared in Swift, the
/// member implementing it in a class of the image that adopts the protocol
/// — directly, or through one of the image's protocols refining it — from
/// the class's Objective-C member table: tied to the class's method by a
/// symbol or thunk at the method's implementation, never by the name alone.
/// Classes are asked in class-list order, and the search stops once every
/// requirement has a member.
package enum ObjCProtocolWitnesses {
    /// `protocolNode` is the protocol's `Protocol` node, the context the
    /// members' declarations are moved to.
    package static func witnesses(for requirements: [ObjCProtocolRequirement], ofProtocolRuntimeName protocolRuntimeName: String, protocolNode: Node, in machO: some MachOSwiftSectionRepresentableWithCache) -> [Int: ObjCProtocolWitness] {
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

        var witnesses: [Int: ObjCProtocolWitness] = [:]
        for adopterRuntimeName in adopterRuntimeNames where witnesses.count < requirements.count {
            guard let (classNode, table) = memberTable(ofClassNamed: adopterRuntimeName, in: machO) else { continue }
            // Selector and kind → the members tied to it; sorted, for a
            // deterministic pick among identical-code-folded twins.
            var symbolNamesByMethod: [MethodKey: [String]] = [:]
            for (symbolName, member) in table.membersByImplementationSymbolName where member.evidence != .selectorName {
                symbolNamesByMethod[MethodKey(selector: member.selector, isClassMethod: member.isClassMethod), default: []].append(symbolName)
            }
            for (index, requirement) in requirements.enumerated() where witnesses[index] == nil {
                let key = MethodKey(selector: requirement.selector, isClassMethod: requirement.isClassMember)
                for symbolName in (symbolNamesByMethod[key] ?? []).sorted() {
                    guard let member = table.membersByImplementationSymbolName[symbolName],
                          let root = try? demangleAsNodeTransient(symbolName),
                          let node = declarationNode(of: root, for: requirement.kind, in: protocolNode)
                    else { continue }
                    // The requirement is declared here, so nothing is
                    // inherited: the selector is spelled out exactly when the
                    // compiler would derive another one from the Swift name,
                    // and whenever that derivation is unknown.
                    let hasExplicitSelector = !(ObjCMemberShape(demangledSymbol: root)?.isDefaultSelector(requirement.selector) ?? false)
                    witnesses[index] = ObjCProtocolWitness(node: node, classNode: classNode, symbolName: symbolName, evidence: member.evidence, hasExplicitSelector: hasExplicitSelector)
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

    /// A Swift class's table is keyed by its qualified name: a member tied
    /// through the thunk's code must belong to that class. Any other class —
    /// one another image defines and this one extends — goes by its runtime
    /// name, as its members' symbols spell it (`__C.NSView`).
    private static func memberTable(ofClassNamed runtimeName: String, in machO: some MachOSwiftSectionRepresentableWithCache) -> (Node, ObjCMemberTable)? {
        if let classNode = ObjCRuntimeNames.swiftClassNode(forRuntimeName: runtimeName, in: machO) {
            guard let qualifiedName = NodeTypeNaming.nominalQualifiedName(of: classNode),
                  let table = ObjCMembers.table(forSwiftClassQualifiedName: qualifiedName, in: machO)
            else { return nil }
            return (classNode, table)
        }
        guard let table = ObjCMembers.table(forObjCClassNamed: runtimeName, in: machO) else { return nil }
        return (ObjCRuntimeNames.classNode(forRuntimeName: runtimeName, in: machO), table)
    }

    /// The member's declaration, as a requirement prints it: the `@objc`
    /// thunk's marker dropped, an initializer's initializing entry point read
    /// as the allocating one the printers recognize, the class's context
    /// replaced by the protocol. A symbol of another kind than the
    /// requirement's — a property's setter where its getter was asked for —
    /// is no witness.
    private static func declarationNode(of root: Node, for kind: ObjCProtocolRequirement.Kind, in protocolNode: Node) -> Node? {
        guard root.kind == .global else { return nil }
        let entities = root.children.filter { $0.kind != .objCAttribute }
        guard entities.count == 1, let entity = entities.first else { return nil }
        let isStatic = entity.kind == .static
        guard let declaration = isStatic ? entity.firstChild : entity else { return nil }
        let rebuiltDeclaration: Node
        switch (kind, declaration.kind) {
        case (.method, .function), (.initializer, .allocator):
            rebuiltDeclaration = Node.createTransient(kind: declaration.kind, children: replacingContext(of: declaration, with: protocolNode))
        case (.initializer, .constructor):
            rebuiltDeclaration = Node.createTransient(kind: .allocator, children: replacingContext(of: declaration, with: protocolNode))
        case (.property, .getter), (.subscript, .getter):
            // The context is the accessed declaration's.
            guard let accessed = declaration.firstChild,
                  accessed.kind == (kind == .property ? .variable : .subscript)
            else { return nil }
            let rebuiltAccessed = Node.createTransient(kind: accessed.kind, children: replacingContext(of: accessed, with: protocolNode))
            rebuiltDeclaration = Node.createTransient(kind: .getter, children: [rebuiltAccessed] + declaration.children.dropFirst())
        default:
            return nil
        }
        let entityNode = isStatic ? Node.createTransient(kind: .static, child: rebuiltDeclaration) : rebuiltDeclaration
        return Node.createTransient(kind: .global, child: entityNode)
    }

    /// A declaration's children with its context — the first child — swapped.
    private static func replacingContext(of declaration: Node, with contextNode: Node) -> [Node] {
        [contextNode] + declaration.children.dropFirst()
    }
}
