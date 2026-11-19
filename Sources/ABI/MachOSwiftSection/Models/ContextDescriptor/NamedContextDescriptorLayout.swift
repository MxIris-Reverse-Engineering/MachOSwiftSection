import Foundation
import MachOBase
import Utilities

@Layout
public protocol NamedContextDescriptorLayout: ContextDescriptorLayout {
    var name: RelativeDirectPointer<String> { get }
}
