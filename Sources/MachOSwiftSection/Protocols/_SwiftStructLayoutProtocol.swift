import Foundation

public protocol _SwiftStructLayoutProtocol {
    associatedtype Pointer: FixedWidthInteger
    var flags: UInt32 { get }
    var parent: Int32 { get }
    var name: Int32 { get }
    var accessFunction: Int32 { get }
    var fieldDescriptor: Int32 { get }
    var numFields: UInt32 { get }
    var fieldOffsetVectorOffset: UInt32 { get }
}

public enum SwiftStructLayoutField {
    case flags
    case parent
    case name
    case accessFunction
    case fieldDescriptor
    case numFields
    case fieldOffsetVectorOffset
}
