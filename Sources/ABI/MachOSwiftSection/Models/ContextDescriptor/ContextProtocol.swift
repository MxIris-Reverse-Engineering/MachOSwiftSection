import Foundation
import MachOKit
import MachOBase

public protocol ContextProtocol: Sendable {
    associatedtype Descriptor: ContextDescriptorProtocol

    var descriptor: Descriptor { get }
}

// MARK: - ReadingContext Support

extension ContextProtocol {
    public func parent(in context: some ReadingContext) throws -> SymbolOrElement<ContextWrapper>? {
        try descriptor.parent(in: context)?.map { try ContextWrapper.forContextDescriptorWrapper($0, in: context) }
    }
}
