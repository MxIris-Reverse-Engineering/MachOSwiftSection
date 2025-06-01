import Foundation
import MachOMacro

@Layout
public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}
