import Foundation
import MachOMacro
import MachOFoundation

@Layout
public protocol ContextDescriptorLayout {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeContextPointer { get }
}
