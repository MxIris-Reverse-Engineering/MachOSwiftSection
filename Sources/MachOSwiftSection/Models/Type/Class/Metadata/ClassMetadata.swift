import MachOKit
import MachOFoundation

public struct ClassMetadata: TypeMetadataProtocol {
    public struct Layout: ClassMetadataLayout {
        public let kind: StoredPointer
        public let superclass: StoredPointer
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

import MachOMacro

@Layout
public protocol AnyClassMetadataLayout: MetadataLayout {
    var superclass: StoredPointer { get }
}

@Layout
public protocol AnyClassMetadataObjCInteropLayout: AnyClassMetadataLayout {
    var cache: RawPointer { get }
    var vtable: RawPointer { get }
    var data: StoredSize { get }
}

@Layout
public protocol ClassMetadataLayout: AnyClassMetadataLayout {
    var flags: UInt32 { get }
    var instanceAddressPoint: UInt32 { get }
    var instanceSize: UInt32 { get }
    var instanceAlignmentMask: UInt16 { get }
    var reserved: UInt16 { get }
    var classSize: UInt32 { get }
    var classAddressPoint: UInt32 { get }
    var descriptor: Pointer<ClassDescriptor> { get }
    var iVarDestroyer: RawPointer { get }
}

@Layout
public protocol ClassMetadataObjCInteropLayout: AnyClassMetadataObjCInteropLayout {
    var flags: UInt32 { get }
    var instanceAddressPoint: UInt32 { get }
    var instanceSize: UInt32 { get }
    var instanceAlignmentMask: UInt16 { get }
    var reserved: UInt16 { get }
    var classSize: UInt32 { get }
    var classAddressPoint: UInt32 { get }
    var descriptor: Pointer<ClassDescriptor> { get }
    var iVarDestroyer: RawPointer { get }
}


@MachOImageAllMembersGenerator
extension ClassMetadataObjCInterop {
    public func fieldOffsets(for descriptor: ClassDescriptor? = nil, in machOFile: MachOFile) throws -> [StoredPointer] {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machOFile)
        guard descriptor.fieldOffsetVectorOffset != .zero else { return [] }
        let offset = offset + descriptor.fieldOffsetVectorOffset.cast() * MemoryLayout<StoredPointer>.size
        return try machOFile.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }
}
