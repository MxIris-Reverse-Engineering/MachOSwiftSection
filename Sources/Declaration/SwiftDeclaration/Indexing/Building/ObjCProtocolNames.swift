import Foundation
import MachOSwiftSection
@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

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
