import Foundation
import MachOSwiftSectionMacro

@Layout
public protocol StructDescriptorLayout: TypeContextDescriptorLayout {
    var numFields: UInt32 { get }
    var fieldOffsetVector: UInt32 { get }
}
