import MachOKit
import MachOSwiftSection
import Demangling
@_spi(Internals) import SwiftInspection

extension ProtocolConformance {
    package func typeNode(in context: some ReadingContext) throws -> Node? {
        return try typeReference.node(in: context)
    }

    package func protocolNode(in context: some ReadingContext) throws -> Node? {
        switch `protocol` {
        case .symbol(let symbol):
            return try SymbolicDemangler.demangleType(for: symbol, in: context)
        case .element(let element):
            return try SymbolicDemangler.demangleContext(for: .protocol(element), in: context)
        case .none:
            return nil
        }
    }
}
