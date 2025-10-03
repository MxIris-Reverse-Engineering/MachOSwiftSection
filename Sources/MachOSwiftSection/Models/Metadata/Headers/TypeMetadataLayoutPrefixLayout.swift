import Foundation
import MachOKit
import MachOFoundation


@Layout
public protocol TypeMetadataLayoutPrefixLayout: LayoutProtocol {
    var layoutString: Pointer<String?> { get }
}
