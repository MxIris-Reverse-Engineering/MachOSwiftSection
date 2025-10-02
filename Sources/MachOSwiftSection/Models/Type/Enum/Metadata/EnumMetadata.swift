import Foundation
import MachOFoundation

public struct EnumMetadata: ResolvableLocatableLayoutWrapper {
    public struct Layout: EnumMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: Pointer<EnumDescriptor>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension EnumMetadata {
    public func payloadSize<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> StoredSize {
        let descriptor = try layout.descriptor.resolve(in: machO)
        let offset = offset.offseting(of: StoredSize.self, numbersOfElements: descriptor.payloadSizeOffset)
        return try machO.readElement(offset: offset)
    }
}
