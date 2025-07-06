import Foundation
import MachOKit
import MachOFoundation

public protocol ContextProtocol: Sendable {
    associatedtype Descriptor: ContextDescriptorProtocol
    
    var descriptor: Descriptor { get }
}

extension ContextProtocol {
    public func parent(in machO: some MachORepresentableWithCache & MachOReadable) throws -> SymbolOrElement<ContextWrapper>? {
        try descriptor.parent(in: machO)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: machO) }
    }
}
