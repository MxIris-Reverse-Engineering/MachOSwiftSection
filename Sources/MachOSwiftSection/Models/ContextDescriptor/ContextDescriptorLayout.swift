import Foundation
import MachOSwiftSectionMacro

@Layout
public protocol ContextDescriptorLayout {
    var flags: ContextDescriptorFlags { get }
    var parent: RelativeContextPointer<ContextDescriptorWrapper?> { get }
}
