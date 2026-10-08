import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension MachOSwiftSection.`Protocol` {
    package func protocolName(in context: some ReadingContext) throws -> ProtocolName {
        try descriptor.protocolName(in: context)
    }
}

extension ProtocolDescriptor {
    package func protocolName(in context: some ReadingContext) throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .protocol(self), in: context), in: context))
    }
}
