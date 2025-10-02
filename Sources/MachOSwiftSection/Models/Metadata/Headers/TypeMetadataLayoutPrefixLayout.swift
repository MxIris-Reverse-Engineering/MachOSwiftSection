import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol TypeMetadataLayoutPrefixLayout: LayoutProtocol {
    var layoutString: Pointer<String?> { get }
}
