import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension TypeDefinition {
    /// Reads the Objective-C protocols the class adopts in its own data
    /// (evolution proposal `swift-declared-objc-protocols`) into
    /// ``objcProtocolNames``. Only a class can; a name several classes print
    /// as finds none.
    package func applyObjCProtocolAdoption(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard typeName.kind == .class,
              let qualifiedName = NodeTypeNaming.nominalQualifiedName(ofDemangledRoot: typeName.node.materialize()),
              let adoption = ObjCProtocolAdoptionIndex.shared.adoption(ofSwiftClassQualifiedName: qualifiedName, in: machO)
        else { return }
        objcProtocolNames = ObjCProtocolNames.protocolNames(adoption.declaredProtocolRuntimeNames, excluding: adoption.impliedProtocolRuntimeNames, in: machO)
    }
}

/// Protocol runtime names as the declaration model's names.
package enum ObjCProtocolNames {
    /// `Type > Protocol` names for `runtimeNames`, without `excluded`.
    package static func protocolNames(_ runtimeNames: [String], excluding excluded: Set<String>, in machO: some MachOSwiftSectionRepresentableWithCache) -> [ProtocolName] {
        runtimeNames.filter { !excluded.contains($0) }.map { runtimeName in
            let typeNode = Node.createTransient(kind: .type, child: ObjCRuntimeNames.protocolNode(forRuntimeName: runtimeName, in: machO))
            return ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: typeNode, in: machO))
        }
    }
}
