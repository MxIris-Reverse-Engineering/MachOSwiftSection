import Foundation

public struct StructMetadata: TypeMetadataProtocol {
    public struct Layout: StructMetadataLayout {
        public let kind: StoredPointer
        public let descriptor: SignedPointer<StructDescriptor>
    }
    
    public var layout: Layout
    
    public let offset: Int
    
    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
    
    public static var descriptorOffset: Int { Layout.offset(of: .descriptor) }
}
