import Foundation
import MachOBase

@Layout
public protocol ContextDescriptorLayout: LayoutProtocol {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeContextPointer { get }
}
