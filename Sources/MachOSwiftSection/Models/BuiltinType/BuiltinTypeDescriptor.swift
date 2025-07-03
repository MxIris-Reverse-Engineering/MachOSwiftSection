import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

public struct BuiltinTypeDescriptor: ResolvableLocatableLayoutWrapper, TopLevelDescriptor {
    public struct Layout: Sendable {
        public let typeName: RelativeDirectPointer<MangledName?>
        public let size: UInt32
        public let alignmentAndFlags: UInt32
        public let stride: UInt32
        public let numExtraInhabitants: UInt32
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension BuiltinTypeDescriptor {
    public func typeName<MachO: MachORepresentableWithCache & MachOReadable>(in machOFile: MachO) throws -> MangledName? {
        return try layout.typeName.resolve(from: offset(of: \.typeName), in: machOFile)
    }

    public var isBitwiseTakable: Bool {
        return (layout.alignmentAndFlags >> 16) & 0x1 != 0
    }

    public var alignment: Int {
        (layout.alignmentAndFlags & 0xFFFF).cast()
    }

    public var hasMangledName: Bool {
        layout.typeName.isNull == false
    }
}
