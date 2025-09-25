import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

public struct MethodOverrideDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let `class`: RelativeContextPointer
        public let method: RelativeMethodDescriptorPointer
        public let implementation: RelativeDirectPointer<Symbol?>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension MethodOverrideDescriptor {
    public func methodDescriptor<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> SymbolOrElement<MethodDescriptor>? {
        return try layout.method.resolve(from: offset(of: \.method), in: machO).asOptional
    }

    public func implementationSymbol<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Symbol? {
        return try layout.implementation.resolve(from: offset(of: \.implementation), in: machO)
    }
}
