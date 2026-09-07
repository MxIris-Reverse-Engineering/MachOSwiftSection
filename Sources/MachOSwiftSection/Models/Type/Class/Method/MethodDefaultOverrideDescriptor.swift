import Foundation
import MachOKit
import MachOBase

public struct MethodDefaultOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectRawPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodDefaultOverrideDescriptor {
    public func originalMethodDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.original.resolve(from: offset(of: \.original), in: machO).asOptional
    }

    public func replacementMethodDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.replacement.resolve(from: offset(of: \.replacement), in: machO).asOptional
    }

    /// File offset of the default-override implementation, or `nil` for a
    /// null pointer. See `MethodDescriptor.implementationOffset`.
    public var implementationOffset: Int? {
        guard layout.implementation.isValid else { return nil }
        return layout.implementation.resolveDirectOffset(from: offset(of: \.implementation))
    }
}

extension MethodDefaultOverrideDescriptor {
    public func originalMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.original.resolve(from: pointer(of: \.original)).asOptional
    }

    public func replacementMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.replacement.resolve(from: pointer(of: \.replacement)).asOptional
    }
}

// MARK: - ReadingContext Support

extension MethodDefaultOverrideDescriptor {
    public func originalMethodDescriptor<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.original.resolve(at: try context.addressFromOffset(offset(of: \.original)), in: context).asOptional
    }

    public func replacementMethodDescriptor<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.replacement.resolve(at: try context.addressFromOffset(offset(of: \.replacement)), in: context).asOptional
    }

    /// The default-override implementation's location as an address in
    /// `context`, or `nil` for a null pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}
