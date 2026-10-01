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

// MARK: - Deprecated Mach-O and pointer forms

extension ContextProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: machO.context).")
    public func parent(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextWrapper>? {
        try parent(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: parent(in: .inProcess).")
    public func parent() throws -> SymbolOrElement<ContextWrapper>? {
        try parent(in: InProcessContext.shared)
    }
}
