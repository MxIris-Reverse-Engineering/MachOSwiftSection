import Foundation
import MachOKit
import MachOBase

@Layout
public protocol TypeMetadataLayoutPrefixLayout: LayoutProtocol {
    var layoutString: Pointer<String?> { get }
}
