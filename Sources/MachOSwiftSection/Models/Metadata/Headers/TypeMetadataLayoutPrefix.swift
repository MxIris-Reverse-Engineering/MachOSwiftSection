import Foundation
import MachOKit
import MachOFoundation


public struct TypeMetadataLayoutPrefix: TypeMetadataLayoutPrefixProtocol {
    public struct Layout: TypeMetadataLayoutPrefixLayout {
        public let layoutString: Pointer<String?>
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}
