import Foundation
import MachOFoundation

@Layout
public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}
