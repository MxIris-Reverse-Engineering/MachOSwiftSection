import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct MethodOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let `class`: RelativeContextPointer
        public let method: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectRawPointer
    }
}

extension MethodOverrideDescriptor {
    /// File offset of the overriding implementation, or `nil` for a null
    /// pointer. See `MethodDescriptor.implementationOffset`.
    public var implementationOffset: Int? {
        resolvedDirectOffset(from: \.implementation)
    }
}

// MARK: - ReadingContext Support

extension MethodOverrideDescriptor {
    public func classDescriptor(in context: some ReadingContext) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try layout.`class`.resolve(at: try context.addressFromOffset(offset(of: \.`class`)), in: context).asOptional
    }

    public func methodDescriptor(in context: some ReadingContext) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(at: try context.addressFromOffset(offset(of: \.method)), in: context).asOptional
    }

    /// The overriding implementation's location as an address in `context`,
    /// or `nil` for a null pointer.
    public func implementationAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let implementationOffset else { return nil }
        return try context.addressFromOffset(implementationOffset)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension MethodOverrideDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: machO.context).")
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        try classDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: methodDescriptor(in: machO.context).")
    public func methodDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> SymbolOrElement<MethodDescriptor>? {
        try methodDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: methodDescriptor(in: .inProcess).")
    public func methodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        try methodDescriptor(in: InProcessContext.shared)
    }
}
