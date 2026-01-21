import Foundation
import MachOKit
import MachOFoundation

public struct MethodDefaultOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let replacement: RelativeMethodDescriptorPointer
        public let original: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<Symbols?>
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
        return try layout.replacement.resolve(from: offset(of: \.original), in: machO).asOptional
    }

    public func implementationSymbols<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> Symbols? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}

extension MethodDefaultOverrideDescriptor {
    public func originalMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.original.resolve(from: pointer(of: \.original)).asOptional
    }

    public func replacementMethodDescriptor() throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.replacement.resolve(from: pointer(of: \.original)).asOptional
    }
}
