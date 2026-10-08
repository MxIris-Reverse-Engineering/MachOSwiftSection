import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct MethodDefaultOverrideDescriptor: ResolvableLocatableLayoutWrapper {
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

// MARK: - Deprecated Mach-O and pointer forms

extension MethodDefaultOverrideDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: originalMethodDescriptor(in: machO.context).")
    public func originalMethodDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<MethodDescriptor>? {
        try originalMethodDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: replacementMethodDescriptor(in: machO.context).")
    public func replacementMethodDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<MethodDescriptor>? {
        try replacementMethodDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: originalMethodDescriptor(in: .inProcess).")
    public func originalMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        try originalMethodDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: replacementMethodDescriptor(in: .inProcess).")
    public func replacementMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        try replacementMethodDescriptor(in: InProcessContext.shared)
    }
}
