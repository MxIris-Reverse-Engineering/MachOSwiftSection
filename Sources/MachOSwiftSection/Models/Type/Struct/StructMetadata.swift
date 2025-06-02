import MachOKit
import MachOMacro
import MachOFoundation

public struct StructMetadata: TypeMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<StructDescriptor>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
    
    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}

@MachOImageAllMembersGenerator
extension StructMetadata {
    public func fieldOffsets(for descriptor: StructDescriptor? = nil, in machOFile: MachOFile) throws -> [UInt32] {
        let descriptor = try descriptor ?? layout.descriptor.resolve(in: machOFile)
        guard descriptor.fieldOffsetVector != .zero else { return [] }
        let offset = offset + descriptor.fieldOffsetVector.cast() * MemoryLayout<StoredPointer>.size
        return try machOFile.readElements(offset: offset, numberOfElements: descriptor.numFields.cast())
    }
}
