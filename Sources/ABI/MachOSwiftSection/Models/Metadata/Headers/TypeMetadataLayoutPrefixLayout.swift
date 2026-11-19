import Foundation
import MachOKit
import MachOBase
import Utilities

@Layout
public protocol TypeMetadataLayoutPrefixLayout: LayoutProtocol {
    var layoutString: Pointer<String?> { get }
}
