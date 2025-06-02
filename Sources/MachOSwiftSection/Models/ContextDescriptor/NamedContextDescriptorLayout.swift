import Foundation
import MachOMacro
import MachOFoundation

@Layout
public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}
