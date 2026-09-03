import Foundation
import MachOKit
import MachOBase

public struct MethodDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: MethodDescriptorFlags
        public let implementation: RelativeDirectRawPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodDescriptor {
    /// File offset of the method's implementation, or `nil` when the pointer
    /// is null (an abstract method, or one whose implementation is not in
    /// this image). Pure pointer arithmetic on the descriptor's own offset —
    /// no reader involved. Attributing symbol names to that offset is
    /// `SwiftInspection`'s `implementationSymbols(in:)`, one layer up.
    public var implementationOffset: Int? {
        guard layout.implementation.isValid else { return nil }
        return layout.implementation.resolveDirectOffset(from: offset(of: \.implementation))
    }
}

// MARK: - ReadingContext Support

extension MethodDescriptor {
    /// The implementation's location as an address in `context` (a file
    /// offset for `MachOContext`, a pointer in-process), or `nil` for a null
    /// pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
