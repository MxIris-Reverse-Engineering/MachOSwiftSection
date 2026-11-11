import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct MethodDefaultOverrideDescriptor {
    public struct Layout: LayoutProtocol {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectRawPointer
    }
}

extension MethodDefaultOverrideDescriptor {
    /// File offset of the default-override implementation, or `nil` for a
    /// null pointer. See `MethodDescriptor.implementationOffset`.
    public var implementationOffset: Int? {
        resolvedDirectOffset(from: \.implementation)
    }
}

// MARK: - ReadingContext Support

extension MethodDefaultOverrideDescriptor {
    public func originalMethodDescriptor(in context: some ReadingContext) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.original.resolve(at: try context.addressFromOffset(offset(of: \.original)), in: context).asOptional
    }

    public func replacementMethodDescriptor(in context: some ReadingContext) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.replacement.resolve(at: try context.addressFromOffset(offset(of: \.replacement)), in: context).asOptional
    }

    /// The default-override implementation's location as an address in
    /// `context`, or `nil` for a null pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
