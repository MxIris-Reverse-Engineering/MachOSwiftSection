import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols
@_spi(Internals) import SwiftInspection

extension MachOSwiftSection.`Protocol` {
    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        try descriptor.protocolName(in: machO)
    }
    
    package func protocolName() throws -> ProtocolName {
        try descriptor.protocolName()
    }
}

extension ProtocolDescriptor {
    package func protocolName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .protocol(self), in: machO), in: machO))
    }
    
    package func protocolName() throws -> ProtocolName {
        ProtocolName(node: InternedNodeReferenceCache.shared.reference(interning: try SymbolicDemangler.demangleContext(for: .protocol(self))))
    }
}
