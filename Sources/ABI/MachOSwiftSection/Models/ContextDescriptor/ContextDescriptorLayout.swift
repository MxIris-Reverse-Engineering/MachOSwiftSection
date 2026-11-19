import Foundation
import MachOBase
import Utilities

@Layout
public protocol ContextDescriptorLayout: LayoutProtocol {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeContextPointer { get }
}
