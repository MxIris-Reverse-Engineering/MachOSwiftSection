import Foundation
import MachOKit
import MachOFoundation

public struct MethodOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let `class`: RelativeContextPointer
        public let method: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<Symbols?>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodOverrideDescriptor {
    public func classDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try layout.`class`.resolve(from: offset(of: \.`class`), in: machO).asOptional
    }

    public func methodDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(from: offset(of: \.method), in: machO).asOptional
    }

    public func methodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(from: pointer(of: \.method)).asOptional
    }

    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbols? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}

// MARK: - ReadingContext Support

extension MethodOverrideDescriptor {
    public func classDescriptor<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<ContextDescriptorWrapper>? {
        return try layout.`class`.resolve(at: try context.addressFromOffset(offset(of: \.`class`)), in: context).asOptional
    }

    public func methodDescriptor<Context: ReadingContext>(in context: Context) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(at: try context.addressFromOffset(offset(of: \.method)), in: context).asOptional
    }

    public func implementationSymbols<Context: ReadingContext>(in context: Context) throws -> Symbols? {
        return try layout.implementation.resolve(at: try context.addressFromOffset(offset(of: \.implementation)), in: context)
    }
}
