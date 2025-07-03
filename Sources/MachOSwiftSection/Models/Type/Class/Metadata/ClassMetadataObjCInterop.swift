import MachOKit
import MachOFoundation
import MachOMacro

public struct ClassMetadataObjCInterop: TypeMetadataProtocol {
    public struct Layout: ClassMetadataObjCInteropLayout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
        public let cache: RawPointer
        public let vtable: RawPointer
        public let data: StoredSize
        public let flags: UInt32
        public let instanceAddressPoint: UInt32
        public let instanceSize: UInt32
        public let instanceAlignmentMask: UInt16
        public let reserved: UInt16
        public let classSize: UInt32
        public let classAddressPoint: UInt32
        public let descriptor: Pointer<ClassDescriptor>
        public let iVarDestroyer: RawPointer
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }

    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}

extension ClassMetadataObjCInterop {
    public func fieldOffsets<MachO: MachORepresentableWithCache & MachOReadable>(for descriptor: ClassDescriptor? = nil, in machO: MachO) throws -> [StoredPointer] {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machO)
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = offset + descriptor.fieldOffsetVectorOffset.cast() * MemoryLayout<StoredPointer>.size
        return try machO.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }
}
