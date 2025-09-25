import Foundation
import MachOMacro
import MachOFoundation

@Layout
public protocol ContextDescriptorLayout: LayoutProtocol {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeContextPointer { get }
}
