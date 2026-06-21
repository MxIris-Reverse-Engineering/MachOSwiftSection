import MachOKit
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

extension ProtocolConformance {
    package func typeNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        return try typeReference.node(in: machO)
    }

    package func typeNode() throws -> Node? {
        return try typeReference.node()
    }

    package func protocolNode<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Node? {
        switch `protocol` {
        case .symbol(let symbol):
            return try MetadataReader.demangleType(for: symbol, in: machO)
        case .element(let element):
            return try MetadataReader.demangleContext(for: .protocol(element), in: machO)
        case .none:
            return nil
        }
    }

    package func protocolNode() throws -> Node? {
        switch `protocol` {
        case .symbol(let symbol):
            return try MetadataReader.demangleType(for: symbol)
        case .element(let element):
            return try MetadataReader.demangleContext(for: .protocol(element))
        case .none:
            return nil
        }
    }
}
